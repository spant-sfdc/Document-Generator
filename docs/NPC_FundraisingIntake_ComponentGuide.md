# NPC Fundraising Intake — OmniStudio Component Guide

**Org:** nonprofit-demo-org-1 (`https://techpulse5.my.salesforce.com`)  
**Platform:** Salesforce Nonprofit Cloud (NPC)  
**Framework:** OmniStudio (LWC-enabled)  
**Total Components:** 14 (1 OmniScript · 4 Integration Procedures · 8 DataRaptors · 1 Deployment Script)

---

## Table of Contents

1. [Solution Overview](#1-solution-overview)
2. [Architecture and Data Flow](#2-architecture-and-data-flow)
3. [OmniScript — NPC_FundraisingIntake](#3-omniscript--npc_fundraisingintake)
4. [Integration Procedures](#4-integration-procedures)
5. [DataRaptors](#5-dataraptors)
6. [Deployment Script](#6-deployment-script)
7. [Salesforce Objects Written](#7-salesforce-objects-written)
8. [Activation Order](#8-activation-order)

---

## 1. Solution Overview

This solution provides a single guided intake form (OmniScript) that covers three fundraising processes for a nonprofit organization:

| Process Type | User selects | Records created |
|---|---|---|
| **Campaign Creation** | "Campaign Creation" | Campaign |
| **Gift Commitment** | "Gift Commitment (Donation / Pledge / Recurring)" | GiftCommitment, GiftCommitmentSchedule (if recurring), GiftDefaultDesignation (per fund) |
| **Grant Intake** | "Grant Intake" | GiftCommitment (type Grant), GiftDefaultDesignation (per fund) |

All three paths share a common donor identification step (search existing Contact or create new Contact + Household Account). No Apex code is used — all data operations are performed through OmniStudio Integration Procedures calling DataRaptors, which call the Salesforce REST API internally.

---

## 2. Architecture and Data Flow

```
┌─────────────────────────────────────────────────────────┐
│              OmniScript: NPC_FundraisingIntake           │
│  Step 1        Step 2       Step 3–4      Step 5–6       │
│  ProcessType → DonorLookup → Details  →  Schedule/Pay   │
│                                          Step 7: Review  │
│                                          ↓ IP Action     │
└─────────────────────┬───────────────────────────────────┘
                      │ calls
                      ▼
┌──────────────────────────────────────────┐
│  IP: NPC_FundraisingOrchestrator         │
│  1. Always: IP → DonorLookupCreate       │
│  2. if Campaign: IP → CampaignCreate     │
│  3. if Donation/Grant: IP → GiftCommitmentCreate │
└──────┬────────────────┬──────────────────┘
       │                │
       ▼                ▼
┌──────────────┐  ┌─────────────────────────────────┐
│ IP:          │  │ IP: NPC_GiftCommitmentCreate     │
│ DonorLookup  │  │  DR Load GiftCommitment          │
│ Create       │  │  if recurring: DR Load Schedule  │
│  ↓Existing:  │  │  Loop: DR Load Designation ×N   │
│  DR Extract  │  └─────────────────────────────────┘
│  ContactById │
│  ↓New:       │  ┌──────────────────────────────┐
│  DR Load     │  │ IP: NPC_CampaignCreate        │
│  Account     │  │  DR Load Campaign             │
│  DR Load     │  └──────────────────────────────┘
│  Contact     │
└──────────────┘
```

---

## 3. OmniScript — NPC_FundraisingIntake

**API Name:** `NPC/FundraisingIntake/1`  
**Type:** OmniScript · LWC-enabled · English  
**File:** `force-app/main/default/omniScripts/NPC_FundraisingIntake_v1.json`

The OmniScript is the user-facing guided form. It collects all information across 8 sequential steps, applies conditional visibility based on `ProcessType`, and submits everything to the orchestrating Integration Procedure on the final step.

---

### Step 1 — ProcessSelection

**Purpose:** Entry point. Lets the user select which of the three fundraising processes they want to initiate. The value chosen here drives all conditional visibility throughout the remaining steps.

| Element | Type | Purpose |
|---|---|---|
| `Intro` | Text Block | Displays welcome HTML: "Welcome to the NPC Fundraising Intake Portal." |
| `ProcessType` | Radio (required) | Three options: `Campaign` · `Donation` · `Grant`. Stored as `ProcessSelection:ProcessType`. |

---

### Step 2 — DonorLookup

**Purpose:** Identifies the donor. Offers two mutually exclusive paths: search an existing Contact record, or enter details to create a new one.

| Element | Type | Purpose |
|---|---|---|
| `DonorExists` | Radio (required) | `Existing` or `New`. Defaults to `Existing`. Controls which child block renders. |
| `ExistingDonorBlock` | Conditional Block | Visible only when `DonorExists = Existing`. |
| `SearchTerm` (inside) | Text | Free-text input for name or email search. |
| `SearchContact` (inside) | DataRaptor Extract Action | Calls `DR_Extract_DonorSearch` with `SearchTerm` as input. Returns `ContactResults[]` list. Fires automatically on entering the block. |
| `SelectedContactId` (inside) | Select | Dropdown populated from `ContactResults[]`, showing Contact Name, storing Contact Id. |
| `NewDonorBlock` | Conditional Block | Visible only when `DonorExists = New`. |
| `FirstName`, `LastName`, `Email`, `Phone` (inside) | Text fields | Collect new donor details. Email and First/Last Name are required. Phone is optional. |

---

### Step 3 — CampaignDetails

**Purpose:** Collects campaign metadata. This step is **only visible when `ProcessType = Campaign`**. Skipped entirely for Donation and Grant flows.

| Element | Type | Purpose |
|---|---|---|
| `CampaignName` | Text (required) | Name for the new Salesforce Campaign record. |
| `CampaignType` | Select (required) | Picklist: Email · Direct Mail · Event · Web · Other. Maps to `Campaign.Type`. |
| `CampaignStartDate` | Date (required) | Maps to `Campaign.StartDate`. |
| `CampaignEndDate` | Date (required) | Maps to `Campaign.EndDate`. |
| `GoalAmount` | Currency (required) | Campaign revenue goal. Passed as `ExpectedRevenue` to the Campaign DR. |

---

### Step 4 — FundDetails

**Purpose:** Collects the financial details of the gift or grant. Renders one of three child blocks based on `ProcessType`.

| Element | Type | Visible when | Purpose |
|---|---|---|---|
| `DonationBlock` | Conditional Block | `ProcessType = Donation` | Container for donation-specific fields. |
| `DonationAmount` (inside) | Currency (required, min 1) | — | Gift amount. Maps to `GiftCommitment.ExpectedTotalCmtAmount`. |
| `GiftFrequency` (inside) | Radio | — | One-Time · Monthly · Annual. Drives whether the Schedule step appears. |
| `GiftType` (inside) | Select | — | Outright Donation · Pledge · Recurring Donation. |
| `GrantBlock` | Conditional Block | `ProcessType = Grant` | Container for grant-specific fields. |
| `GrantRequestedAmount` (inside) | Currency (required, min 1) | — | Requested grant amount. |
| `GrantCategory` (inside) | Select | — | Education · Healthcare · Environment · Community · Arts · Research · Other. |
| `RequiresApproval` (inside) | Toggle (default: true) | — | Flags this grant for manual approval review. |
| `CampaignFundBlock` | Conditional Block | `ProcessType = Campaign` | Secondary campaign financial fields. |
| `ExpectedRevenue` (inside) | Currency (optional) | — | Expected revenue for the campaign. |
| `CampaignDescription` (inside) | Text, multiline (optional) | — | Free-text description of the campaign. |

---

### Step 5 — Allocation

**Purpose:** Specifies how the gift should be split across one or more designated funds. Applies to all three process types. The repeating group lets users add multiple fund designations, each with a name and a percentage.

| Element | Type | Purpose |
|---|---|---|
| `AllocationNote` | Text Block | Instruction text: "Percentages must total 100%." |
| `AllocationGroup` | Edit Block (repeating) | Repeating group with "Add Fund" / "Remove" controls. Each row holds one fund designation entry. |
| `FundName` (inside) | Text (required) | Name of the fund to receive the allocation. |
| `AllocationPercentage` (inside) | Number (required, 1–100) | Percentage of the gift going to this fund. |

The full `AllocationGroup` array is passed as-is to the Integration Procedure, which loops through it to create one `GiftDefaultDesignation` record per entry.

---

### Step 6 — Schedule

**Purpose:** Collects recurring payment schedule details. This step is **only visible when `ProcessType = Donation` AND `GiftFrequency ≠ One-time`**. It is skipped for one-time gifts, grants, and campaign flows.

| Element | Type | Purpose |
|---|---|---|
| `RecurringStartDate` | Date (required) | First payment date. Maps to `GiftCommitmentSchedule.StartDate`. |
| `NumberOfInstallments` | Number (optional, default 0) | How many installments. 0 means open-ended (no end date). |
| `AmountPerInstallment` | Currency (required, min 1) | Per-payment amount. Maps to `GiftCommitmentSchedule.TransactionAmount`. |
| `InstallmentFrequency` | Select (required) | Monthly · Quarterly · Yearly. Maps to `GiftCommitmentSchedule.TransactionPeriod`. |

---

### Step 7 — PaymentSetup

**Purpose:** Captures how payment will be made. Shown for all process types.

| Element | Type | Purpose |
|---|---|---|
| `PaymentInstrumentType` | Select (required) | Credit Card · Debit Card · Bank Transfer (ACH) · UPI · Check · Other. |
| `PaymentMethod` | Select (required) | Online Portal · Manual Entry · Offline. Maps to `GiftCommitmentSchedule.PaymentMethod`. |
| `PaymentReference` | Text (optional) | Check number or other reference. |

---

### Step 8 — ReviewAndSubmit

**Purpose:** Final step. Displays a read-only summary of all entries, then fires the Integration Procedure to persist everything to Salesforce. Shows success or error feedback after submission.

| Element | Type | Purpose |
|---|---|---|
| `ReviewHeader` | Text Block | "Please review the information below before submitting." |
| `FundraisingSummary` | Review Action | Auto-renders all filled fields from every step in an accordion. `showAllSteps: true`, `expandAll: true`. |
| `SubmitFundraisingIntake` | Integration Procedure Action | Calls `NPC/FundraisingOrchestrator`. Fires `onStepEnter`. Passes 26 input parameters covering all collected data. Receives `ContactId`, `GiftCommitmentId`, `CampaignId`, `SuccessMessage`, `ErrorMessage`. |
| `SuccessBlock` | Conditional Block | Visible when `SuccessMessage ≠ ""`. Shows green success text with the returned record ID. |
| `ErrorBlock` | Conditional Block | Visible when `ErrorMessage ≠ ""`. Shows red error text. |

---

## 4. Integration Procedures

Integration Procedures (IPs) are server-side logic containers. They execute all data operations — no DML happens in the OmniScript layer itself. All four IPs are deployed under the `NPC` type namespace.

---

### IP 1 — NPC_FundraisingOrchestrator

**API Name:** `NPC/FundraisingOrchestrator/1`  
**File:** `force-app/main/default/integrationProcedures/NPC_FundraisingOrchestrator_v1.json`  
**Called by:** OmniScript `SubmitFundraisingIntake` action on the ReviewAndSubmit step.

**Purpose:** Top-level orchestrator. Receives the full payload from the OmniScript and routes execution to the correct child IPs based on `ProcessType`. Always resolves the donor first, then branches.

**Execution Order:**

| Step | Element | Type | Condition | Action |
|---|---|---|---|---|
| 1 | `InitializeOutput` | Set Values | Always | Pre-initializes all output variables to empty/null: `Result:ContactId`, `Result:AccountId`, `Result:CampaignId`, `Result:GiftCommitmentId`, `Result:ScheduleIds`, `Result:DesignationIds`, `Result:SuccessMessage`, `Result:ErrorMessage`. |
| 2 | `DonorLookupCreate` | IP Action | Always | Calls `NPC/DonorLookupCreate`. Passes `DonorExists`, `SelectedContactId`, `FirstName`, `LastName`, `Email`, `Phone`. Returns `ContactId` and `AccountId`. |
| 3 | `SetContactId` | Set Values | Always | Promotes `DonorResult:ContactId` and `DonorResult:AccountId` into the main `Result` namespace. |
| 4 | `IsCampaignProcess` | Conditional Block | `ProcessType = Campaign` | Calls `NPC/CampaignCreate` IP, then sets `Result:CampaignId`. |
| 5 | `IsDonationOrGrantProcess` | Conditional Block | `ProcessType ≠ Campaign` | Calls `NPC/GiftCommitmentCreate` IP, then sets `Result:GiftCommitmentId`, `Result:ScheduleIds`, `Result:DesignationIds`. |
| 6 | `SetSuccessResponse` | Response Action | Always | Builds final response object with success message and all record IDs. |

---

### IP 2 — NPC_DonorLookupCreate

**API Name:** `NPC/DonorLookupCreate/1`  
**File:** `force-app/main/default/integrationProcedures/NPC_DonorLookupCreate_v1.json`  
**Called by:** `NPC_FundraisingOrchestrator` → `DonorLookupCreate` step.

**Purpose:** Resolves or creates the donor Contact record. Handles two mutually exclusive paths — existing donor lookup vs. new donor creation. Returns `ContactId` and `AccountId` to the orchestrator regardless of which path ran.

**Execution Order:**

| Step | Element | Type | Condition | Action |
|---|---|---|---|---|
| 1 | `InitDonorOutput` | Set Values | Always | Initializes `DonorResult:ContactId`, `DonorResult:AccountId`, `DonorResult:IsNew` to empty/false. |
| 2 | `IsExistingDonor` | Conditional Block | `DonorExists = Existing` | Runs the existing-donor sub-flow. |
| 2a | `FetchExistingContact` | DR Extract Action | (inside block) | Calls `DR_Extract_ContactById` with `ContactId = SelectedContactId`. Returns Contact.Id and Contact.AccountId. |
| 2b | `SetExistingContactIds` | Set Values | (inside block) | Copies returned IDs into `DonorResult:ContactId`, `DonorResult:AccountId`. Sets `IsNew = false`. |
| 3 | `IsNewDonor` | Conditional Block | `DonorExists = New` | Runs the new-donor creation sub-flow. |
| 3a | `CreateAccount` | DR Load Action | (inside block) | Calls `DR_Load_Account`. Creates a Household Account with `Name = LastName + " Household"` and RecordType resolved to `Household`. Returns `NewAccountId`. |
| 3b | `CreateContact` | DR Load Action | (inside block) | Calls `DR_Load_Contact`. Creates a Contact (upsert on Email) linked to the new Account. Returns `NewContactId`. |
| 3c | `SetNewDonorIds` | Set Values | (inside block) | Copies `NewContactId` / `NewAccountId` into `DonorResult` namespace. Sets `IsNew = true`. |
| 4 | `DonorResponse` | Response Action | Always | Returns `DonorResult:ContactId`, `DonorResult:AccountId`, `DonorResult:IsNew` to the calling orchestrator. |

---

### IP 3 — NPC_CampaignCreate

**API Name:** `NPC/CampaignCreate/1`  
**File:** `force-app/main/default/integrationProcedures/NPC_CampaignCreate_v1.json`  
**Called by:** `NPC_FundraisingOrchestrator` → `IsCampaignProcess` block.

**Purpose:** Creates a single Salesforce `Campaign` record and returns its Id. The simplest of the four IPs — three elements, no branching.

**Execution Order:**

| Step | Element | Type | Action |
|---|---|---|---|
| 1 | `InitCampaignOutput` | Set Values | Initializes `CampaignResult:CampaignId` to empty string. |
| 2 | `CreateCampaignRecord` | DR Load Action | Calls `DR_Load_Campaign`. Passes Name, Type, StartDate, EndDate, ExpectedRevenue, Description. Static values Status=Planning and IsActive=true are injected by the DR itself. Returns `CampaignId`. |
| 3 | `CampaignResponse` | Response Action | Returns `CampaignResult:CampaignId` to the orchestrator. |

---

### IP 4 — NPC_GiftCommitmentCreate

**API Name:** `NPC/GiftCommitmentCreate/1`  
**File:** `force-app/main/default/integrationProcedures/NPC_GiftCommitmentCreate_v1.json`  
**Called by:** `NPC_FundraisingOrchestrator` → `IsDonationOrGrantProcess` block.

**Purpose:** The most complex IP. Creates a `GiftCommitment` record, optionally creates a `GiftCommitmentSchedule` for recurring gifts, and loops through the fund allocation entries to create one `GiftDefaultDesignation` per fund. Handles both Donation and Grant process types by normalizing the amount into a shared variable.

**Execution Order:**

| Step | Element | Type | Condition | Action |
|---|---|---|---|---|
| 1 | `InitGiftOutput` | Set Values | Always | Initializes `GiftResult:GiftCommitmentId`, `GiftResult:ScheduleIds`, `GiftResult:DesignationIds`, `ComputedAmount = 0`, `ComputedType = ""`. |
| 2 | `IsDonation` | Conditional Block | `ProcessType = Donation` | Sets `ComputedAmount = DonationAmount`, `ComputedType = GiftType`. |
| 3 | `IsGrant` | Conditional Block | `ProcessType = Grant` | Sets `ComputedAmount = GrantRequestedAmount`, `ComputedType = "Grant"`. |
| 4 | `CreateGiftCommitmentRecord` | DR Load Action | Always | Calls `DR_Load_GiftCommitment`. Passes `ContactId`, `ComputedAmount`, `ComputedType`, `GiftFrequency`, `PaymentMethod`, and other fields. Returns `GiftCommitmentId`. |
| 5 | `IsRecurringGift` | Conditional Block | `GiftFrequency ≠ One-time AND ProcessType = Donation` | Creates the recurring payment schedule. |
| 5a | `CreateScheduleRecords` | DR Load Action | (inside block) | Calls `DR_Load_GiftCommitmentSchedule`. Passes `GiftCommitmentId`, `RecurringStartDate`, `AmountPerInstallment`, `InstallmentFrequency`. DR injects static `Type = CreateTransactions`. Returns `ScheduleId`. |
| 6 | `CreateDesignations` | Loop Block | Always | Iterates over every entry in `AllocationGroup[]`. Loop variable is `CurrentAllocation`. |
| 6a | `CreateDesignationRecord` | DR Load Action | (per loop iteration) | Calls `DR_Load_Designation` with `GiftCommitmentId` and `CurrentAllocation:AllocationPercentage`. Creates one `GiftDefaultDesignation` record per fund. Returns `NewDesignationId`. |
| 7 | `GiftResponse` | Response Action | Always | Returns `GiftResult:GiftCommitmentId`, `GiftResult:ScheduleIds`, `GiftResult:DesignationIds` to the orchestrator. |

---

## 5. DataRaptors

DataRaptors are the data-mapping layer. They translate between the JSON payload format used by Integration Procedures and Salesforce SObject records. No Apex and no direct SOQL is written — the DataRaptor engine handles all queries and DML internally.

Two types are used:
- **Extract** — queries Salesforce records and returns JSON
- **Load** — receives JSON and inserts/updates/upserts Salesforce records

---

### DR 1 — DR_Extract_ContactById

**Type:** Extract · Source Object: `Contact`  
**File:** `force-app/main/default/dataRaptors/DR_Extract_ContactById_v1.json`  
**Called by:** `NPC_DonorLookupCreate` → `FetchExistingContact`

**Purpose:** Fetches a single Contact record by its Salesforce Id. Used when the user selects an existing donor from the search results to confirm the record exists and retrieve its linked `AccountId`.

**Filter Conditions:**

| Field | Operator | Value | Group |
|---|---|---|---|
| `Contact.Id` | `=` | `%ContactId%` (input parameter) | 1 |

**Output Fields:**

| SObject Field | JSON Output Path |
|---|---|
| `Contact.Id` | `Id` |
| `Contact.FirstName` | `FirstName` |
| `Contact.LastName` | `LastName` |
| `Contact.Email` | `Email` |
| `Contact.Phone` | `Phone` |
| `Contact.AccountId` | `AccountId` |

---

### DR 2 — DR_Extract_DonorSearch

**Type:** Extract · Source Object: `Contact`  
**File:** `force-app/main/default/dataRaptors/DR_Extract_DonorSearch_v1.json`  
**Called by:** OmniScript `DonorLookup` step → `SearchContact` DR Lookup Action

**Purpose:** Searches Contacts by partial name OR partial email. The two filter groups implement OR logic — FilterGroup 1 matches on Name, FilterGroup 2 matches on Email. Results are returned as an array (`ContactResults[]`) used to populate the "Select Donor" dropdown in the OmniScript.

**Filter Conditions:**

| Field | Operator | Value | Group | Logic |
|---|---|---|---|---|
| `Contact.Name` | `LIKE` | `%%SearchTerm%%` (wildcard match) | 1 | OR |
| `Contact.Email` | `LIKE` | `%%SearchTerm%%` (wildcard match) | 2 | OR |

*Different FilterGroup numbers = OR logic between them.*

**Output Fields (array path `ContactResults[]`):**

| SObject Field | JSON Output Path |
|---|---|
| `Contact.Id` | `ContactResults[].Id` |
| `Contact.Name` | `ContactResults[].Name` |
| `Contact.FirstName` | `ContactResults[].FirstName` |
| `Contact.LastName` | `ContactResults[].LastName` |
| `Contact.Email` | `ContactResults[].Email` |
| `Contact.Phone` | `ContactResults[].Phone` |
| `Contact.AccountId` | `ContactResults[].AccountId` |

---

### DR 3 — DR_Load_Account

**Type:** Load · Target Object: `Account`  
**File:** `force-app/main/default/dataRaptors/DR_Load_Account_v1.json`  
**Called by:** `NPC_DonorLookupCreate` → `CreateAccount`

**Purpose:** Creates a Household Account for a new donor. Uses a cross-object lookup to resolve the RecordType developer name `Household` to its Salesforce Id — avoiding hard-coded RecordType IDs. Returns the new Account Id so the Contact can be linked to it.

**Field Mappings:**

| Mapping Type | JSON Input | SObject Field | Notes |
|---|---|---|---|
| `load_input` | `AccountName` | `Account.Name` | IP computes as `LastName + " Household"` |
| `load_lookup` | `RecordTypeDeveloperName` | `Account.RecordTypeId` | Looks up `RecordType` where `DeveloperName = 'Household'`, returns `Id` |
| `load_static` | — | `Account.Type` | Always sets to `"Household"` |
| `load_id_output` | — | `Account.Id` | Captures new record Id as `NewAccountId` |

---

### DR 4 — DR_Load_Contact

**Type:** Load · Target Object: `Contact`  
**File:** `force-app/main/default/dataRaptors/DR_Load_Contact_v1.json`  
**Called by:** `NPC_DonorLookupCreate` → `CreateContact`

**Purpose:** Creates a new donor Contact and links it to the Household Account created in the previous step. Uses Email as an **upsert key** — if a Contact with the same email already exists, it is updated rather than duplicated.

**Field Mappings:**

| Mapping Type | JSON Input | SObject Field | Notes |
|---|---|---|---|
| `load_input` | `FirstName` | `Contact.FirstName` | |
| `load_input` | `LastName` | `Contact.LastName` | |
| `load_input` | `Email` | `Contact.Email` | **Upsert key** — prevents duplicates |
| `load_input` | `Phone` | `Contact.Phone` | |
| `load_input` | `AccountId` | `Contact.AccountId` | Links to the Household Account |
| `load_id_output` | — | `Contact.Id` | Captures created/updated Id as `NewContactId` |

---

### DR 5 — DR_Load_Campaign

**Type:** Load · Target Object: `Campaign`  
**File:** `force-app/main/default/dataRaptors/DR_Load_Campaign_v1.json`  
**Called by:** `NPC_CampaignCreate` → `CreateCampaignRecord`

**Purpose:** Creates a Salesforce Campaign record. All input values come from the OmniScript CampaignDetails step via the IP. Two static values (Status and IsActive) are injected by the DR, so the IP does not need to hardcode them.

**Field Mappings:**

| Mapping Type | JSON Input | SObject Field | Notes |
|---|---|---|---|
| `load_input` | `CampaignName` | `Campaign.Name` | |
| `load_input` | `CampaignType` | `Campaign.Type` | Email / Direct Mail / Event / Web / Other |
| `load_input` | `CampaignStartDate` | `Campaign.StartDate` | |
| `load_input` | `CampaignEndDate` | `Campaign.EndDate` | |
| `load_input` | `ExpectedRevenue` | `Campaign.ExpectedRevenue` | |
| `load_input` | `CampaignDescription` | `Campaign.Description` | |
| `load_static` | — | `Campaign.Status` | Always `"Planning"` |
| `load_static` | — | `Campaign.IsActive` | Always `"true"` |
| `load_id_output` | — | `Campaign.Id` | Captures new Id as `CampaignId` |

---

### DR 6 — DR_Load_GiftCommitment

**Type:** Load · Target Object: `GiftCommitment` (NPC standard object)  
**File:** `force-app/main/default/dataRaptors/DR_Load_GiftCommitment_v1.json`  
**Called by:** `NPC_GiftCommitmentCreate` → `CreateGiftCommitmentRecord`

**Purpose:** Creates a `GiftCommitment` record — the core NPC object representing a donor's financial pledge. Key design notes: uses `DonorId` (not a custom `Contact__c` field) for the Contact relationship; `Status` is always injected as `Active` by the DR. The IP pre-computes `ScheduleType` and `RecurrenceType` before calling this DR.

**Field Mappings:**

| Mapping Type | JSON Input | SObject Field | Notes |
|---|---|---|---|
| `load_input` | `ContactId` | `GiftCommitment.DonorId` | NPC uses `DonorId`, not `Contact__c` |
| `load_input` | `CampaignId` | `GiftCommitment.CampaignId` | Optional campaign linkage |
| `load_input` | `GiftCommitmentName` | `GiftCommitment.Name` | Composed by IP as "DonorName - GiftType" |
| `load_input` | `DonationAmount` | `GiftCommitment.ExpectedTotalCmtAmount` | Total pledged amount |
| `load_input` | `DonationAmount` | `GiftCommitment.NextTransactionAmount` | Amount for the next payment |
| `load_input` | `EffectiveStartDate` | `GiftCommitment.EffectiveStartDate` | When the commitment begins |
| `load_input` | `ScheduleType` | `GiftCommitment.ScheduleType` | `Recurring` or `Custom` (for one-time) |
| `load_input` | `RecurrenceType` | `GiftCommitment.RecurrenceType` | `OpenEnded` or `FixedLength` |
| `load_static` | — | `GiftCommitment.Status` | Always `"Active"` |
| `load_id_output` | — | `GiftCommitment.Id` | Captures new Id as `GiftCommitmentId` |

---

### DR 7 — DR_Load_GiftCommitmentSchedule

**Type:** Load · Target Object: `GiftCommitmentSchedule` (NPC standard object)  
**File:** `force-app/main/default/dataRaptors/DR_Load_GiftCommitmentSchedule_v1.json`  
**Called by:** `NPC_GiftCommitmentCreate` → `IsRecurringGift` → `CreateScheduleRecords`

**Purpose:** Creates a `GiftCommitmentSchedule` record that drives automatic recurring transaction generation in NPC. Only called when `GiftFrequency ≠ One-time`. The static `Type = CreateTransactions` is required by NPC to activate the schedule engine — without it, no transactions are generated.

**Field Mappings:**

| Mapping Type | JSON Input | SObject Field | Notes |
|---|---|---|---|
| `load_input` | `GiftCommitmentId` | `GiftCommitmentSchedule.GiftCommitmentId` | Links schedule to the parent commitment |
| `load_input` | `RecurringStartDate` | `GiftCommitmentSchedule.StartDate` | First payment date |
| `load_input` | `AmountPerInstallment` | `GiftCommitmentSchedule.TransactionAmount` | Per-installment amount |
| `load_input` | `InstallmentFrequency` | `GiftCommitmentSchedule.TransactionPeriod` | `Monthly` / `Yearly` / `Weekly` / `Daily` / `Custom` |
| `load_input` | `TransactionInterval` | `GiftCommitmentSchedule.TransactionInterval` | Every N periods (e.g. 1 = every month, 3 = quarterly) |
| `load_input` | `TotalScheduleAmount` | `GiftCommitmentSchedule.TotalScheduleAmount` | Total across all installments (0 if open-ended) |
| `load_input` | `PaymentMethod` | `GiftCommitmentSchedule.PaymentMethod` | Credit Card / ACH / Check / Cash |
| `load_static` | — | `GiftCommitmentSchedule.Type` | Always `"CreateTransactions"` — activates NPC schedule engine |
| `load_id_output` | — | `GiftCommitmentSchedule.Id` | Captures new Id as `ScheduleId` |

---

### DR 8 — DR_Load_Designation

**Type:** Load · Target Object: `GiftDefaultDesignation` (NPC standard object)  
**File:** `force-app/main/default/dataRaptors/DR_Load_Designation_v1.json`  
**Called by:** `NPC_GiftCommitmentCreate` → `CreateDesignations` loop → `CreateDesignationRecord`

**Purpose:** Creates a `GiftDefaultDesignation` record for each fund in the allocation list. `GiftDefaultDesignation` is the NPC junction object that links a `GiftCommitment` to a `GiftDesignation` (fund record) with a specified percentage. Called once per loop iteration — if the user entered 3 fund allocations, this DR is called 3 times.

**Important:** `GiftDesignationId` must be a valid Salesforce Id of an existing `GiftDesignation` record. The IP or OmniScript must resolve the fund name to this Id before calling the DR.

**Field Mappings:**

| Mapping Type | JSON Input | SObject Field | Notes |
|---|---|---|---|
| `load_input` | `GiftCommitmentId` | `GiftDefaultDesignation.ParentRecordId` | Links designation to the parent GiftCommitment |
| `load_input` | `GiftDesignationId` | `GiftDefaultDesignation.GiftDesignationId` | The fund record Id to designate the gift to |
| `load_input` | `AllocationPercentage` | `GiftDefaultDesignation.AllocatedPercentage` | e.g., `50` = 50% |
| `load_id_output` | — | `GiftDefaultDesignation.Id` | Captures new Id as `NewDesignationId` |

---

## 6. Deployment Script

**File:** `scripts/deploy_omnistudio.py`  
**Language:** Python 3 (stdlib only — no pip dependencies)  
**Usage:** `python3 scripts/deploy_omnistudio.py [--target-org <alias>]`  
**Default org alias:** `nonprofit-demo-org-1`

**Purpose:** Automates deployment of all 14 OmniStudio artifacts to any Salesforce org via REST API. Used because the standard `sf omnistudio` CLI plugin was not available. Reads credentials from `sf org display` and performs idempotent deployments — detects existing records, deletes their children, and re-creates them from the JSON definitions.

**Deployment order (hardcoded for dependency safety):**

1. All 8 DataRaptors (alphabetical — no inter-DR dependencies)
2. Integration Procedures in dependency order: `DonorLookupCreate` → `CampaignCreate` → `GiftCommitmentCreate` → `FundraisingOrchestrator`
3. OmniScript

**Key functions:**

| Function | Purpose |
|---|---|
| `get_creds(alias)` | Calls `sf org display --json` to retrieve access token and instance URL. |
| `deploy_dataraptor(token, base, json_path)` | Creates `OmniDataTransform` header if not exists; deletes existing items; calls `_deploy_dr_item` for each `mapItems` entry. |
| `_deploy_dr_item(token, base, dr_id, item, seq)` | Handles all 6 item types via `_type` switch: `filter`, `extract_output`, `load_input`, `load_static`, `load_lookup`, `load_id_output`. Each builds the correct `OmniDataTransformItem` API body. |
| `deploy_process(token, base, json_path)` | Creates `OmniProcess` header if not exists; deletes existing elements; calls `_deploy_elements` recursively. |
| `_deploy_elements(...)` | Recursively walks `children[]` arrays to create `OmniProcessElement` records with correct parent-child hierarchy via `ParentElementId`. |
| `_delete_dr_items(token, base, dr_id)` | Queries and DELETEs all existing `OmniDataTransformItem` records for a DR before re-creating. |
| `_delete_process_elements(token, base, process_id)` | Queries and DELETEs all existing `OmniProcessElement` records for an IP/OmniScript before re-creating. |
| `_request(method, url, token, body, retries=3)` | HTTP wrapper with automatic retry on 502/503/429 (exponential backoff). |

**DataRaptor item type → API field mapping:**

| `_type` | Key API fields set on `OmniDataTransformItem` |
|---|---|
| `filter` | `InputObjectName`, `LookupByFieldName` (filter field), `FilterOperator`, `FilterGroup`, `FilterValue` |
| `extract_output` | `InputObjectName`, `InputFieldName` (SObject field), `OutputFieldName` (JSON path), `LinkedFieldName` |
| `load_input` | `OutputObjectName`, `InputFieldName` (JSON key), `OutputFieldName` (SObject field), `LinkedFieldName`, `IsUpsertKey` (if applicable) |
| `load_static` | `OutputObjectName`, `OutputFieldName`, `LinkedFieldName`, `DefaultValue` |
| `load_lookup` | `OutputObjectName`, `OutputFieldName`, `InputFieldName`, `LookupObjectName`, `LookupByFieldName`, `LookupReturnedFieldName` |
| `load_id_output` | `InputObjectName`, `InputFieldName = "Id"`, `OutputFieldName` (JSON path), `LinkedFieldName = "Id"` |

---

## 7. Salesforce Objects Written

| SObject | Written by DR | NPC Standard Object? | Notes |
|---|---|---|---|
| `Account` | DR_Load_Account | No (core SF) | Household type, RecordType looked up dynamically |
| `Contact` | DR_Load_Contact | No (core SF) | Upsert on Email |
| `Campaign` | DR_Load_Campaign | No (core SF) | Standard Campaign object |
| `GiftCommitment` | DR_Load_GiftCommitment | Yes | Core NPC giving record |
| `GiftCommitmentSchedule` | DR_Load_GiftCommitmentSchedule | Yes | Drives recurring transaction generation |
| `GiftDefaultDesignation` | DR_Load_Designation | Yes | Junction: GiftCommitment ↔ GiftDesignation (fund) |

---

## 8. Activation Order

After deployment, activate components in this order in OmniStudio Designer. Activating out of order will cause runtime errors because components reference each other by name.

```
Step 1 — Activate all 8 DataRaptors (any order)
  ✓ DR_Extract_ContactById
  ✓ DR_Extract_DonorSearch
  ✓ DR_Load_Account
  ✓ DR_Load_Contact
  ✓ DR_Load_Campaign
  ✓ DR_Load_GiftCommitment
  ✓ DR_Load_GiftCommitmentSchedule
  ✓ DR_Load_Designation

Step 2 — Activate Integration Procedures (in this order)
  ✓ NPC_DonorLookupCreate      (depends on DR_Extract_ContactById, DR_Load_Account, DR_Load_Contact)
  ✓ NPC_CampaignCreate         (depends on DR_Load_Campaign)
  ✓ NPC_GiftCommitmentCreate   (depends on DR_Load_GiftCommitment, DR_Load_GiftCommitmentSchedule, DR_Load_Designation)
  ✓ NPC_FundraisingOrchestrator (depends on all three child IPs above)

Step 3 — Activate OmniScript
  ✓ NPC_FundraisingIntake      (depends on NPC_FundraisingOrchestrator, DR_Extract_DonorSearch)
```

**To embed the OmniScript in a Lightning page or Experience Cloud site:**  
Use the standard `omniscript/FundraisingIntake` LWC component with `type="NPC"` and `subtype="FundraisingIntake"`.
