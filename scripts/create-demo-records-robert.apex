// ── Step 1: Account ──────────────────────────────────────────────────────────
Account acc = new Account(
    Name          = 'Robert Thomas',
    Donor_ID__c   = 'DON-2026-0041',
    Donor_Type__c = 'Major Donor',
    Type          = 'Individual'
);
insert acc;
System.debug('ACCOUNT_ID=' + acc.Id);

// ── Step 2: Opportunity ───────────────────────────────────────────────────────
Opportunity opp = new Opportunity(
    Name             = '$71000 Major Gift – Robert Thomas',
    AccountId        = acc.Id,
    Amount           = 71000,
    CloseDate        = Date.newInstance(2026, 9, 2),
    StageName        = 'Closed Won',
    Donation_Type__c = 'One-Time Major Gift',
    Campaign_Name__c = 'Education Support Fund'
);
insert opp;
System.debug('OPPORTUNITY_ID=' + opp.Id);

// ── Step 3A: Get Standard Pricebook (reuse existing) ─────────────────────────
Id pricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
opp.Pricebook2Id = pricebookId;
update opp;

// ── Step 3B: Create Products ──────────────────────────────────────────────────
Product2 prodAF = new Product2(Name = 'Annual Fund',       IsActive = true);
Product2 prodPS = new Product2(Name = 'Programme Support', IsActive = true);
insert new List<Product2>{ prodAF, prodPS };

// ── Step 3C: Create Pricebook Entries ─────────────────────────────────────────
PricebookEntry pbeAF = new PricebookEntry(
    Pricebook2Id = pricebookId,
    Product2Id   = prodAF.Id,
    UnitPrice    = 50000,
    IsActive     = true
);
PricebookEntry pbePS = new PricebookEntry(
    Pricebook2Id = pricebookId,
    Product2Id   = prodPS.Id,
    UnitPrice    = 21000,
    IsActive     = true
);
insert new List<PricebookEntry>{ pbeAF, pbePS };

// ── Step 3D: Opportunity Line Items ───────────────────────────────────────────
List<OpportunityLineItem> items = new List<OpportunityLineItem>{
    new OpportunityLineItem(
        OpportunityId        = opp.Id,
        PricebookEntryId     = pbeAF.Id,
        Contribution_Type__c = 'Annual Fund',
        Quantity             = 1,
        UnitPrice            = 50000
    ),
    new OpportunityLineItem(
        OpportunityId        = opp.Id,
        PricebookEntryId     = pbePS.Id,
        Contribution_Type__c = 'Programme Support',
        Quantity             = 1,
        UnitPrice            = 21000
    )
};
insert items;

// ── Verify Amount rollup ──────────────────────────────────────────────────────
Opportunity verify = [SELECT Amount FROM Opportunity WHERE Id = :opp.Id];
Boolean conditionMet = verify.Amount > 10000;

System.debug('--- CREATION COMPLETE ---');
System.debug('Account Id:      ' + acc.Id);
System.debug('Opportunity Id:  ' + opp.Id);
System.debug('Line Item 1 Id:  ' + items[0].Id + '  (Annual Fund     x1 @ $50,000)');
System.debug('Line Item 2 Id:  ' + items[1].Id + '  (Programme Support x1 @ $21,000)');
System.debug('Opportunity Amount (rollup): $' + verify.Amount);
System.debug('Variable condition Amount > 10000: ' + conditionMet);
