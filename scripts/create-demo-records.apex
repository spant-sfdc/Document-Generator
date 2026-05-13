// ── Step 1: Account ──────────────────────────────────────────────────────────
Account acc = new Account(
    Name          = 'John Carter',
    Donor_ID__c   = 'DON-1001',
    Donor_Type__c = 'Individual'
);
insert acc;
System.debug('ACCOUNT_ID=' + acc.Id);

// ── Step 2: Opportunity ───────────────────────────────────────────────────────
Opportunity opp = new Opportunity(
    Name              = 'Education Support Fund',
    AccountId         = acc.Id,
    Amount            = 15000,
    Campaign_Name__c  = 'Education for All 2026',
    Donation_Type__c  = 'Grant',
    Total_Donation__c = 15000,
    StageName         = 'Closed Won',
    CloseDate         = Date.today()
);
insert opp;
System.debug('OPPORTUNITY_ID=' + opp.Id);

// ── Step 3: Link Opportunity to Standard Pricebook ────────────────────────────
List<Pricebook2> pbs = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1];
Id pricebookId = pbs[0].Id;
opp.Pricebook2Id = pricebookId;
update opp;

// ── Step 4: Products & PricebookEntries ──────────────────────────────────────
// Books
Product2 prodBooks = new Product2(Name = 'Books', IsActive = true);
insert prodBooks;
PricebookEntry pbeBooks = new PricebookEntry(
    Pricebook2Id = pricebookId,
    Product2Id   = prodBooks.Id,
    UnitPrice    = 100,
    IsActive     = true
);
insert pbeBooks;

// Scholarship
Product2 prodScholarship = new Product2(Name = 'Scholarship', IsActive = true);
insert prodScholarship;
PricebookEntry pbeScholarship = new PricebookEntry(
    Pricebook2Id = pricebookId,
    Product2Id   = prodScholarship.Id,
    UnitPrice    = 5000,
    IsActive     = true
);
insert pbeScholarship;

// ── Step 5: OpportunityLineItems ──────────────────────────────────────────────
List<OpportunityLineItem> items = new List<OpportunityLineItem>{
    new OpportunityLineItem(
        OpportunityId        = opp.Id,
        PricebookEntryId     = pbeBooks.Id,
        Contribution_Type__c = 'Books',
        Quantity             = 10,
        UnitPrice            = 100
    ),
    new OpportunityLineItem(
        OpportunityId        = opp.Id,
        PricebookEntryId     = pbeScholarship.Id,
        Contribution_Type__c = 'Scholarship',
        Quantity             = 1,
        UnitPrice            = 5000
    )
};
insert items;

System.debug('OLI_IDS=' + new List<Id>{ items[0].Id, items[1].Id });
System.debug('--- DONE ---');
System.debug('Account Id: '     + acc.Id);
System.debug('Opportunity Id: ' + opp.Id);
System.debug('LineItem 1 Id: '  + items[0].Id);
System.debug('LineItem 2 Id: '  + items[1].Id);
