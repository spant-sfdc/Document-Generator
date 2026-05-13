// ═══════════════════════════════════════════════════════════════════
// DocGen Demo Data — Robert Thomas Foundation
// Target org  : rupali-np-org (akshitadhyani-kprr@force.com)
// Scenario    : $71,000 Major Gift | Education Support Fund
// Covers      : parent mapping, child table, formula variable
// ═══════════════════════════════════════════════════════════════════

// ── 0. Guard: avoid duplicates ────────────────────────────────────
List<Account> existing = [SELECT Id FROM Account WHERE Name = 'Robert Thomas Foundation' LIMIT 1];
if (!existing.isEmpty()) {
    System.debug('⚠️  Account already exists: ' + existing[0].Id + '. Delete first or run cleanup script.');
    return;
}

// ── 1. Account — Donor Organization ──────────────────────────────
Account acc = new Account(
    Name             = 'Robert Thomas Foundation',
    Type             = 'Other',
    Donor_Type__c    = 'Foundation',
    Donor_ID__c      = 'DON-2026-RTF-001',
    Phone            = '+1 (212) 555-0192',
    Website          = 'www.robertthomasfoundation.org',
    AnnualRevenue    = 5000000,
    BillingStreet    = '1250 Broadway, Suite 3600',
    BillingCity      = 'New York',
    BillingState     = 'NY',
    BillingPostalCode= '10001',
    BillingCountry   = 'United States',
    Description      = 'Private philanthropic organization committed to advancing educational equity and academic excellence across underserved communities in the United States.'
);
insert acc;
System.debug('✅ ACCOUNT_ID=' + acc.Id);

// ── 2. Contact — Primary Donor ────────────────────────────────────
Contact con = new Contact(
    AccountId    = acc.Id,
    FirstName    = 'Robert',
    LastName     = 'Thomas',
    Title        = 'Founder & Executive Director',
    Email        = 'r.thomas@rtfoundation.org',
    Phone        = '+1 (212) 555-0192',
    MobilePhone  = '+1 (917) 555-0147',
    Department   = 'Executive Leadership',
    MailingStreet    = '1250 Broadway, Suite 3600',
    MailingCity      = 'New York',
    MailingState     = 'NY',
    MailingPostalCode= '10001',
    MailingCountry   = 'United States'
);
insert con;
System.debug('✅ CONTACT_ID=' + con.Id);

// ── 3. Opportunity — Major Gift Proposal ─────────────────────────
Opportunity opp = new Opportunity(
    Name             = '$71,000 Major Gift – Robert Thomas',
    AccountId        = acc.Id,
    Amount           = 71000,
    StageName        = 'Proposal/Price Quote',
    CloseDate        = Date.newInstance(2026, 9, 30),
    Donation_Type__c = 'One-Time',
    Campaign_Name__c = 'Education Support Fund',
    Total_Donation__c= 71000,
    LeadSource       = 'Word of mouth',
    Description      = 'Proposed major gift of $71,000 from the Robert Thomas Foundation in support of the 2026 Education Support Fund initiative. Funds will be allocated toward annual programming ($50,000) and scholarship support ($21,000) for under-resourced students across partner institutions.'
);
insert opp;
System.debug('✅ OPPORTUNITY_ID=' + opp.Id);

// ── 4. Contact Role — link Robert Thomas as Decision Maker ────────
OpportunityContactRole ocr = new OpportunityContactRole(
    OpportunityId = opp.Id,
    ContactId     = con.Id,
    Role          = 'Decision Maker',
    IsPrimary     = true
);
insert ocr;
System.debug('✅ CONTACT_ROLE_ID=' + ocr.Id);

// ── 5. Link Opportunity to Standard Pricebook ─────────────────────
Id pricebookId = [SELECT Id FROM Pricebook2 WHERE IsStandard = true LIMIT 1].Id;
opp.Pricebook2Id = pricebookId;
update opp;

// ── 6. Products ───────────────────────────────────────────────────
Product2 prodAF = new Product2(
    Name        = 'Annual Fund',
    Description = 'Core annual fund contribution supporting operational programs and community outreach.',
    IsActive    = true
);
Product2 prodPS = new Product2(
    Name        = 'Programme Support',
    Description = 'Targeted funding for scholarship and academic support programs.',
    IsActive    = true
);
insert new List<Product2>{ prodAF, prodPS };

// ── 7. Pricebook Entries ──────────────────────────────────────────
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

// ── 8. Opportunity Line Items ─────────────────────────────────────
List<OpportunityLineItem> items = new List<OpportunityLineItem>{
    new OpportunityLineItem(
        OpportunityId        = opp.Id,
        PricebookEntryId     = pbeAF.Id,
        Contribution_Type__c = 'Annual Fund',
        Description          = 'Core annual fund contribution for 2026 programming cycle.',
        Quantity             = 1,
        UnitPrice            = 50000
    ),
    new OpportunityLineItem(
        OpportunityId        = opp.Id,
        PricebookEntryId     = pbePS.Id,
        Contribution_Type__c = 'Programme Support',
        Description          = 'Dedicated scholarship support for 14 student recipients.',
        Quantity             = 1,
        UnitPrice            = 21000
    )
};
insert items;
System.debug('✅ OLI_1_ID=' + items[0].Id + '  (Annual Fund x1 @ $50,000)');
System.debug('✅ OLI_2_ID=' + items[1].Id + '  (Programme Support x1 @ $21,000)');

// ── 9. Validate ───────────────────────────────────────────────────
Opportunity verify = [
    SELECT Amount, Is_Major_Donor__c, Campaign_Name__c, Donation_Type__c
    FROM Opportunity
    WHERE Id = :opp.Id
];

System.debug('');
System.debug('══════════════════════════════════════════════');
System.debug('  DocGen Demo Data — Creation Complete');
System.debug('══════════════════════════════════════════════');
System.debug('  Account      : Robert Thomas Foundation');
System.debug('  Account Id   : ' + acc.Id);
System.debug('  Contact      : Robert Thomas (Founder & Executive Director)');
System.debug('  Contact Id   : ' + con.Id);
System.debug('  Opportunity  : $71,000 Major Gift – Robert Thomas');
System.debug('  Opp Id       : ' + opp.Id);
System.debug('  Stage        : Proposal/Price Quote');
System.debug('  Campaign     : ' + verify.Campaign_Name__c);
System.debug('  Donation Type: ' + verify.Donation_Type__c);
System.debug('  Amount       : $' + verify.Amount);
System.debug('  Is Major Donor (formula): ' + verify.Is_Major_Donor__c);
System.debug('  OLI 1        : Annual Fund         x1 @ $50,000  Id=' + items[0].Id);
System.debug('  OLI 2        : Programme Support   x1 @ $21,000  Id=' + items[1].Id);
System.debug('══════════════════════════════════════════════');
System.debug('  DocGen Readiness:');
System.debug('    ✓ Parent mapping  — Account + Opportunity fields populated');
System.debug('    ✓ Child table     — 2 OLIs with Contribution_Type__c');
System.debug('    ✓ Formula var     — Is_Major_Donor__c = ' + verify.Is_Major_Donor__c);
System.debug('    ✓ Contact role    — Robert Thomas as Decision Maker (primary)');
System.debug('══════════════════════════════════════════════');
