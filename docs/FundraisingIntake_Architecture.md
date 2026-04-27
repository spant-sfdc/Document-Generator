# NPC Fundraising Intake — OmniStudio Architecture

## Overview

Reusable OmniScript (`NPC / FundraisingIntake / v1`) that drives three Nonprofit Cloud fundraising workflows from a single entry point:

| Process | Outcome Records |
|---|---|
| **Campaign Creation** | Campaign, (Contact link) |
| **Gift Commitment** | Gift_Commitment__c, Gift_Commitment_Schedule__c (if recurring), Designation__c |
| **Grant Intake** | Gift_Commitment__c (Type=Grant), Designation__c |

---

## Architecture Layers

```
┌─────────────────────────────────────────────────────────┐
│               OMNISCRIPT (UI Layer)                     │
│   NPC / FundraisingIntake / v1                          │
│   8 Steps · Conditional branching · Group repeater      │
└────────────────────────┬────────────────────────────────┘
                         │ Integration Procedure Action
                         ▼
┌─────────────────────────────────────────────────────────┐
│           ORCHESTRATOR IP (Logic Layer)                 │
│   NPC / FundraisingOrchestrator / v1                    │
│   Routes to child IPs based on ProcessType              │
└──────┬──────────────┬──────────────┬────────────────────┘
       │              │              │
       ▼              ▼              ▼
  DonorLookup    CampaignCreate  GiftCommitment
  Create IP          IP           Create IP
       │                              │
       ▼                              ▼
┌─────────────────┐         ┌─────────────────────────────┐
│  DATA LAYER     │         │  DATA LAYER                 │
│  DR_Load_Contact│         │  DR_Load_GiftCommitment     │
│  DR_Load_Account│         │  DR_Load_GiftCommitmentSched│
│                 │         │  DR_Load_Designation        │
└─────────────────┘         └─────────────────────────────┘
```

---

## OmniScript Step Flow

### Step 1 — ProcessSelection
- **Element:** Radio `ProcessType`
- **Values:** `Campaign` | `Donation` | `Grant`
- **Controls:** Conditional display of Steps 3, 4 (CampaignDetails, GrantBlock/DonationBlock)

### Step 2 — DonorLookup
- **Element:** Radio `DonorExists` → `Existing` | `New`
- **Existing path:** Text `SearchTerm` → DR Lookup Action → Select `SelectedContactId`
- **New path:** Text inputs for FirstName, LastName, Email, Phone (inside `NewDonorBlock` Conditional View)

### Step 3 — CampaignDetails _(shown only if ProcessType = Campaign)_
- CampaignName, CampaignType (picklist), StartDate, EndDate, GoalAmount

### Step 4 — FundDetails
- **DonationBlock** _(ProcessType = Donation)_: Amount, GiftFrequency, GiftType
- **GrantBlock** _(ProcessType = Grant)_: RequestedAmount, GrantCategory, RequiresApproval toggle
- **CampaignFundBlock** _(ProcessType = Campaign)_: ExpectedRevenue, Description

### Step 5 — Allocation
- Repeating Group (`AllocationGroup`): FundName + AllocationPercentage per entry
- User can add/remove fund rows

### Step 6 — Schedule _(shown only if Donation AND GiftFrequency ≠ One-time)_
- RecurringStartDate, NumberOfInstallments (0 = open-ended), AmountPerInstallment, InstallmentFrequency

### Step 7 — PaymentSetup
- PaymentInstrumentType, PaymentMethod, PaymentReference

### Step 8 — ReviewAndSubmit
- Built-in `Review` element shows all steps as summary
- On step enter → fires IP Action `SubmitFundraisingIntake`
- Success/Error Conditional Views display result

---

## Integration Procedure Designs

### IP 1: NPC / FundraisingOrchestrator

**Purpose:** Entry point from the OmniScript. Delegates to child IPs.

| # | Action | Type | Notes |
|---|---|---|---|
| 1 | InitializeOutput | Set Values | Seeds all Result: output vars |
| 2 | DonorLookupCreate | IP Action | Always runs; returns ContactId, AccountId |
| 3 | SetContactId | Set Values | Copies donor output to Result |
| 4 | IsCampaignProcess | Conditional | Runs if ProcessType = Campaign |
| ↳ 4a | CreateCampaign | IP Action | Calls NPC/CampaignCreate |
| ↳ 4b | SetCampaignId | Set Values | Maps result |
| 5 | IsDonationOrGrantProcess | Conditional | Runs if ProcessType ≠ Campaign |
| ↳ 5a | CreateGiftCommitment | IP Action | Calls NPC/GiftCommitmentCreate |
| ↳ 5b | SetGiftIds | Set Values | Maps GiftCommitmentId, ScheduleIds |
| 6 | SetSuccessResponse | Response Action | Builds final output for OmniScript |

---

### IP 2: NPC / DonorLookupCreate

**Purpose:** Either retrieves existing Contact or creates new Contact + Household Account.

| # | Action | Type | Notes |
|---|---|---|---|
| 1 | InitDonorOutput | Set Values | Seeds ContactId, AccountId |
| 2 | IsExistingDonor | Conditional | DonorExists = Existing |
| ↳ 2a | FetchExistingContact | DR Extract | DR_Extract_ContactById |
| ↳ 2b | SetExistingContactIds | Set Values | |
| 3 | IsNewDonor | Conditional | DonorExists = New |
| ↳ 3a | CreateAccount | DR Load | DR_Load_Account (Household) |
| ↳ 3b | CreateContact | DR Load | DR_Load_Contact (upsert on Email) |
| ↳ 3c | SetNewDonorIds | Set Values | |
| 4 | DonorResponse | Response Action | Returns ContactId, AccountId |

---

### IP 3: NPC / CampaignCreate

**Purpose:** Creates Campaign record.

| # | Action | Type | Notes |
|---|---|---|---|
| 1 | InitCampaignOutput | Set Values | |
| 2 | CreateCampaignRecord | DR Load | DR_Load_Campaign |
| 3 | CampaignResponse | Response Action | Returns CampaignId |

---

### IP 4: NPC / GiftCommitmentCreate

**Purpose:** Creates Gift Commitment, optional Schedule records, and Designation records.

| # | Action | Type | Notes |
|---|---|---|---|
| 1 | InitGiftOutput | Set Values | |
| 2 | IsDonation | Conditional | Sets ComputedAmount from DonationAmount |
| 3 | IsGrant | Conditional | Sets ComputedAmount from GrantRequestedAmount; Type=Grant |
| 4 | CreateGiftCommitmentRecord | DR Load | DR_Load_GiftCommitment |
| 5 | IsRecurringGift | Conditional | GiftFrequency ≠ One-time AND ProcessType = Donation |
| ↳ 5a | CreateScheduleRecords | DR Load | DR_Load_GiftCommitmentSchedule |
| 6 | CreateDesignations | Loop Action | Iterates over AllocationGroup |
| ↳ 6a | CreateDesignationRecord | DR Load | DR_Load_Designation per iteration |
| 7 | GiftResponse | Response Action | Returns GiftCommitmentId, ScheduleIds |

---

## DataRaptor Catalog

| Name | Type | Target Object | Upsert Key | Purpose |
|---|---|---|---|---|
| DR_Extract_DonorSearch | Extract | Contact | — | SOQL search by name/email; returns list |
| DR_Extract_ContactById | Extract | Contact | — | Fetch single Contact by ID |
| DR_Load_Contact | Load | Contact | Email | Upsert donor Contact |
| DR_Load_Account | Load | Account | — | Create Household Account |
| DR_Load_Campaign | Load | Campaign | — | Insert Campaign |
| DR_Load_GiftCommitment | Load | Gift_Commitment__c | — | Insert Gift Commitment |
| DR_Load_GiftCommitmentSchedule | Load | Gift_Commitment_Schedule__c | — | Insert recurring schedule |
| DR_Load_Designation | Load | Designation__c | — | Insert fund designation per allocation |

---

## Data Model Reference

### Standard Objects Used

```
Contact
  ├─ FirstName, LastName, Email, Phone
  └─ AccountId (→ Household Account)

Account
  ├─ Name (e.g. "Smith Household")
  ├─ Type = Household
  └─ RecordType = HH_Account

Campaign
  ├─ Name, Type, Status
  ├─ StartDate, EndDate
  ├─ ExpectedRevenue, Description
  └─ IsActive
```

### NPC Custom Objects

```
Gift_Commitment__c
  ├─ Contact__c (lookup → Contact)
  ├─ Account__c (lookup → Account)
  ├─ Amount__c
  ├─ Type__c                   — Donation | Pledge | RecurringDonation | Grant
  ├─ Process_Type__c           — Campaign | Donation | Grant
  ├─ Frequency__c              — One-time | Monthly | Yearly
  ├─ Grant_Category__c
  ├─ Requires_Approval__c
  ├─ Payment_Instrument_Type__c
  ├─ Payment_Method__c
  ├─ Payment_Reference__c
  └─ Status__c

Gift_Commitment_Schedule__c
  ├─ Gift_Commitment__c (lookup → Gift_Commitment__c)
  ├─ Scheduled_Date__c
  ├─ Amount__c
  ├─ Frequency__c
  ├─ Start_Date__c
  ├─ Number_of_Installments__c
  └─ Status__c

Designation__c
  ├─ Gift_Commitment__c (lookup → Gift_Commitment__c)
  ├─ Fund_Name__c
  ├─ Allocation_Percentage__c
  └─ Status__c
```

---

## Assumptions

1. **NPC Package installed** — Assumes Salesforce Nonprofit Cloud (NPC) package is installed with `Gift_Commitment__c`, `Gift_Commitment_Schedule__c`, and `Designation__c` objects. Confirm exact API names in Setup > Object Manager.

2. **Household Account model** — New donors get a Household Account created automatically. If your org uses a different account model (e.g., One-to-One), adjust `DR_Load_Account` and remove the Account creation step.

3. **No grant-specific object** — Grant intake reuses `Gift_Commitment__c` with `Type__c = Grant`. If your org has a separate Grant/FundingRequest object (e.g., `outfunds__Funding_Request__c`), swap the DR target in `DR_Load_GiftCommitment`.

4. **Contact deduplication** — DR_Load_Contact uses `Email` as the upsert key. If a Contact with the same email already exists, it will be updated (not duplicated). Adjust if your org uses a different dedup strategy.

5. **OmniStudio LWC runtime** — `bIsLwcEnabled: true` assumes OmniStudio is running on the LWC runtime (Salesforce 226+). If using Aura runtime, set this to `false`.

6. **Percentage validation** — The OmniScript does not include a server-side validation that allocation percentages sum to 100. Add a Formula element in the Allocation step or a validation action in the IP.

7. **Payment processing** — No live payment gateway integration is included. `PaymentInstrumentType` and `PaymentMethod` are stored as metadata only. Extend with a Payment Gateway IP Action if needed.

8. **Grant approval workflow** — `RequiresApproval__c = true` flags the record. Actual approval routing must be configured separately via Salesforce Approvals or Flow.

9. **Recurring schedule generation** — Schedule records are created as a single header record (not individual installment records) unless a loop is added in the IP to compute and insert one record per installment date.

10. **API version** — All metadata targets `sourceApiVersion: 66.0` (Spring '25). OmniStudio version 240+ is assumed.

---

## SFDX Project Structure

```
force-app/main/default/
│
├── omniScripts/
│   └── NPC_FundraisingIntake_v1.json          ← Main OmniScript (8 steps)
│
├── integrationProcedures/
│   ├── NPC_FundraisingOrchestrator_v1.json    ← Top-level orchestrator
│   ├── NPC_DonorLookupCreate_v1.json          ← Contact/Account create or lookup
│   ├── NPC_CampaignCreate_v1.json             ← Campaign insert
│   └── NPC_GiftCommitmentCreate_v1.json       ← Gift + Schedule + Designation
│
├── dataRaptors/
│   ├── DR_Extract_DonorSearch_v1.json         ← SOQL search for donor autocomplete
│   ├── DR_Extract_ContactById_v1.json         ← Fetch Contact by ID
│   ├── DR_Load_Contact_v1.json               ← Upsert Contact (key: Email)
│   ├── DR_Load_Account_v1.json               ← Insert Household Account
│   ├── DR_Load_Campaign_v1.json              ← Insert Campaign
│   ├── DR_Load_GiftCommitment_v1.json        ← Insert Gift Commitment
│   ├── DR_Load_GiftCommitmentSchedule_v1.json← Insert recurring schedule
│   └── DR_Load_Designation_v1.json           ← Insert fund designation
│
└── docs/
    └── FundraisingIntake_Architecture.md      ← This file
```

---

## Deployment Steps

### Prerequisites
```bash
# Install OmniStudio CLI plugin (if not already installed)
sf plugins install @salesforce/plugin-omnistudio

# Authenticate to org
sf org login web --alias npc-demo-org
```

### Option A: OmniStudio Designer Import (Recommended for initial setup)

1. Open **OmniStudio > OmniScripts** in your org
2. Click **Import** → upload `NPC_FundraisingIntake_v1.json`
3. Open **OmniStudio > Integration Procedures** → import all 4 IP JSONs in this order:
   - `NPC_DonorLookupCreate_v1.json`
   - `NPC_CampaignCreate_v1.json`
   - `NPC_GiftCommitmentCreate_v1.json`
   - `NPC_FundraisingOrchestrator_v1.json`
4. Open **OmniStudio > DataRaptors** → import all 8 DR JSONs
5. Activate each artifact in reverse dependency order: DRs → IPs → OmniScript

### Option B: SFDX Deploy

```bash
# Deploy OmniStudio metadata (requires OmniStudio CLI plugin)
sf omnistudio:deploy --manifest manifest/package.xml --target-org npc-demo-org

# Or deploy all source
sf project deploy start --source-dir force-app --target-org npc-demo-org
```

### Manifest Entry (`manifest/package.xml`)

```xml
<types>
  <members>NPC_FundraisingIntake_1</members>
  <name>OmniScript</name>
</types>
<types>
  <members>NPC_FundraisingOrchestrator_1</members>
  <members>NPC_DonorLookupCreate_1</members>
  <members>NPC_CampaignCreate_1</members>
  <members>NPC_GiftCommitmentCreate_1</members>
  <name>IntegrationProcedure</name>
</types>
<types>
  <members>DR_Extract_DonorSearch</members>
  <members>DR_Extract_ContactById</members>
  <members>DR_Load_Contact</members>
  <members>DR_Load_Account</members>
  <members>DR_Load_Campaign</members>
  <members>DR_Load_GiftCommitment</members>
  <members>DR_Load_GiftCommitmentSchedule</members>
  <members>DR_Load_Designation</members>
  <name>DataRaptor</name>
</types>
```

### Post-Deployment Checklist

- [ ] Confirm custom field API names on `Gift_Commitment__c` match DR mappings
- [ ] Confirm `Designation__c` object exists with `Fund_Name__c` and `Allocation_Percentage__c`
- [ ] Validate `DR_Load_Account` Record Type lookup resolves to correct `HH_Account` RecordType
- [ ] Test `DR_Extract_DonorSearch` SOQL in Query Editor
- [ ] Activate DRs first, then IPs, then OmniScript
- [ ] Add OmniScript to FlexiPage or Community/Experience Cloud page
- [ ] Assign OmniScript to appropriate Profile/Permission Set via OmniStudio Access Policies

---

## Extensibility Notes

| Extension | Where to add |
|---|---|
| Payment gateway (Stripe, Cybersource) | New HTTP Action in `NPC_GiftCommitmentCreate` after DR_Load_GiftCommitment |
| Duplicate donor detection | DR Extract before DR_Load_Contact in `NPC_DonorLookupCreate` |
| Campaign membership on gift | New DR_Load_CampaignMember step in Orchestrator IP |
| Soft credit / tribute gift | New OmniScript step + Designation__c fields |
| Gift Transaction (receipt) | Extend Orchestrator IP with DR_Load_GiftTransaction after commitment |
| Multi-language support | Set `sLanguage` per locale variant; duplicate OmniScript with translated labels |
