# Document Generator (DocGen) — Complete Reference

**Org:** nonprofit-demo-org-1 (`spant-9csk@force.com` · https://techpulse5.my.salesforce.com)  
**API Version:** 66.0  
**Prepared:** April 2026

---

## Table of Contents

1. [What Is DocGen?](#1-what-is-docgen)
2. [Architecture Overview](#2-architecture-overview)
3. [Data Model](#3-data-model)
4. [Custom Metadata Configuration](#4-custom-metadata-configuration)
5. [Apex Classes](#5-apex-classes)
6. [Lightning Web Components](#6-lightning-web-components)
7. [Visualforce Page](#7-visualforce-page)
8. [App, Tabs & Navigation](#8-app-tabs--navigation)
9. [Permission Set](#9-permission-set)
10. [Sample Template](#10-sample-template)
11. [Token Reference](#11-token-reference)
12. [End-to-End Usage Guide](#12-end-to-end-usage-guide)
13. [Folder Structure](#13-folder-structure)

---

## 1. What Is DocGen?

DocGen is a native Salesforce document generation framework built entirely with LWC, Apex, and standard platform features — no managed packages, no external services. It allows users to:

- Upload an HTML template containing merge tokens (`{{TokenName}}`)
- Map each token to a Salesforce object field, a constant, or a system variable
- Merge live record data into the template at runtime
- Preview the merged document inline
- Download the output as a styled PDF or Word file
- Store the generated document as a Salesforce File (ContentVersion) linked to any record

Everything is self-contained within the org and deployable as source metadata.

---

## 2. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                  LWC Wizard (6 Steps)               │
│  Upload → Object → Fields → Mapping → Variables → Preview/Download │
└────────────────────┬────────────────────────────────┘
                     │ @AuraEnabled callouts
┌────────────────────▼────────────────────────────────┐
│              DocGen_Controller  (Apex)              │
│          Central entry point for all LWC calls      │
└──┬────────┬────────┬────────┬────────┬──────────────┘
   │        │        │        │        │
   ▼        ▼        ▼        ▼        ▼
Schema  Template  DataResolver  Merge  Variable
Service  Service   Service    Engine  Resolver
   │        │        │          │        │
   └────────┴────────┴──────────┴────────┘
                     │
           ┌─────────▼──────────┐
           │  DocumentGenerator │  ──► FileService ──► ContentVersion
           │     Service        │  ──► VF PDF Page
           └────────────────────┘
```

**Key design principles:**
- All SOQL injection prevention via `Schema.getGlobalDescribe()` field validation and regex whitelisting
- FLS/CRUD checked using `isAccessible()`, `isCreateable()`, and `WITH SECURITY_ENFORCED`
- No external callouts — PDF is generated via a Visualforce page's `getContentAsPDF()` method
- Token format is `{{TokenName}}` for fields, `{{sys.variableName}}` for system variables, `{{#SectionName}}...{{/SectionName}}` for repeating sections, `{{#if field}}...{{/if}}` for conditionals

---

## 3. Data Model

### 3.1 Document_Template__c

**Purpose:** Master record for each document template. Stores the reference to the uploaded template file and its configuration.

| Field | API Name | Type | Purpose |
|---|---|---|---|
| Name | Name | Auto Number | Unique identifier (e.g. TMPL-0001) |
| Primary Object | Primary_Object__c | Text (255) | API name of the Salesforce object this template runs against |
| Template File ID | Template_Content_Version_Id__c | Text (18) | ContentVersion Id of the uploaded HTML template file |
| Status | Status__c | Picklist | Draft / Active / Archived — controls availability |
| Version | Version__c | Number | Template version number |
| Language | Language__c | Text (10) | Locale code (e.g. en-US) |
| Is Active | Is_Active__c | Checkbox | Quick toggle to enable/disable without archiving |
| Description | Description__c | Text Area (500) | Free-text notes about the template |

**Sharing:** ReadWrite (standard OWD, respects sharing rules)

---

### 3.2 Document_Field_Mapping__c

**Purpose:** Each record maps one token in the template to a data source — a Salesforce field, a constant value, a variable, or an expression. Child of Document_Template__c.

| Field | API Name | Type | Purpose |
|---|---|---|---|
| Name | Name | Auto Number | DMAP-0001, DMAP-0002, … |
| Template | Template__c | Master-Detail (Template) | Parent template |
| Token Name | Token_Name__c | Text (100) | The token as it appears in the template, e.g. `{{DonorName}}` |
| Source Object | Source_Object__c | Text (100) | API name of the object the field comes from |
| Source Field | Source_Field__c | Text (100) | API name of the field |
| Relationship Path | Relationship_Path__c | Text (255) | Dot-notation path for cross-object fields, e.g. `Account.Name` |
| Mapping Type | Mapping_Type__c | Picklist | FIELD / CONSTANT / VARIABLE / EXPRESSION |
| Is Repeating Section | Is_Repeating_Section__c | Checkbox | True if this token drives a `{{#Section}}...{{/Section}}` block |
| Format Override | Format_Override__c | Text (50) | Format directive: date / currency / number / upper / lower |
| Static Value | Static_Value__c | Text Area (1000) | Value used when Mapping Type is CONSTANT |
| Repeat Object | Repeat_Object__c | Text (100) | API name of the child object to iterate for repeating sections |

**Sharing:** ControlledByParent

---

### 3.3 Document_Variable__c

**Purpose:** Stores variables and constants that are resolved at document generation time — system dates, current user info, org details, or static image references. Child of Document_Template__c.

| Field | API Name | Type | Purpose |
|---|---|---|---|
| Name | Name | Text | Variable name as used in the template |
| Template | Template__c | Master-Detail (Template) | Parent template |
| Variable Type | Variable_Type__c | Picklist | SYSTEM_DATE / CURRENT_USER / ORG_NAME / CONSTANT / IMAGE |
| Static Value | Static_Value__c | Text Area (1000) | Value for CONSTANT type |
| Image File ID | Image_Content_Version_Id__c | Text (18) | ContentVersion Id for IMAGE type; embedded as base64 in the output |

**Sharing:** ControlledByParent

---

### 3.4 Document_Generation_Log__c

**Purpose:** Audit trail. Every time a document is generated, a log record is created capturing what was generated, when, for which record, and whether it succeeded.

| Field | API Name | Type | Purpose |
|---|---|---|---|
| Name | Name | Auto Number | LOG-0001, LOG-0002, … |
| Template | Template__c | Lookup (Template) | Which template was used |
| Record ID | Record_Id__c | Text (18) | Salesforce ID of the source record |
| Generated At | Generated_At__c | DateTime | Timestamp of generation |
| Status | Status__c | Picklist | Success / Failed |
| Error Message | Error_Message__c | Long Text Area | Full error detail if generation failed |
| Output File ID | Output_Content_Document_Id__c | Text (18) | ContentDocument Id of the generated file |

**Sharing:** ReadWrite

---

## 4. Custom Metadata Configuration

**Type:** `DocGen_Config__mdt`  
**Purpose:** Centralised org-level configuration that drives framework behaviour. Edited in Setup → Custom Metadata Types → DocGen Config → Manage Records → Default. Changes take effect immediately without a code deployment.

### Record: Default

| Field | API Name | Value | Purpose |
|---|---|---|---|
| PDF Page Size | PDF_Page_Size__c | Letter | Page size passed to the PDF renderer |
| Default Date Format | Default_Date_Format__c | MM/dd/yyyy | Format applied when no Format Override is set on a date field |
| Max Repeating Rows | Max_Repeating_Rows__c | 200 | Safety cap on how many rows a repeating section can render |
| Org Display Name | Org_Display_Name__c | Hope Forward Foundation | Overrides the platform org name in `{{sys.orgName}}` |
| Org EIN | Org_EIN__c | 47-1234567 | Tax ID auto-resolved as `{{sys.orgEIN}}` |
| Org Address | Org_Address__c | 123 Mission Way, Suite 400… | Mailing address auto-resolved as `{{sys.orgAddress}}` |
| Org Phone | Org_Phone__c | (415) 555-0192 | Phone auto-resolved as `{{sys.orgPhone}}` |
| Org Website | Org_Website__c | www.hopeforwardfoundation.org | Website auto-resolved as `{{sys.orgWebsite}}` |

All `Org_*` fields are exposed automatically as `{{sys.*}}` tokens in every template — no wizard mapping step required.

---

## 5. Apex Classes

### 5.1 DocGen_Controller
**Type:** `with sharing` · `@AuraEnabled` entry point  
**Purpose:** Single controller consumed by all LWC components. Validates inputs, delegates to service classes, and wraps all exceptions as `AuraHandledExceptions` so the UI receives readable error messages.

| Method | Cacheable | Purpose |
|---|---|---|
| `getObjects()` | Yes | Returns all queryable, accessible SObjects sorted A–Z |
| `getFields(objectName)` | Yes | Returns all accessible fields for a given object |
| `getRelatedObjects(objectName)` | Yes | Returns parent and child objects reachable from the given object |
| `extractTokens(contentVersionId)` | No | Reads the uploaded template and returns all `{{tokens}}` found |
| `uploadTemplate(base64Content, fileName)` | No | Decodes base64, creates a ContentVersion, returns its Id |
| `saveTemplateConfig(configJson)` | No | Persists the completed wizard config as Template + child records |
| `generatePreview(configJson)` | No | Resolves data and returns merged HTML for inline preview |
| `generateDocument(configJson, format, linkedRecordId)` | No | Generates PDF or Word, saves to Files, returns ContentDocument Id |
| `getTemplates()` | Yes | Returns all Active Document_Template__c records |

---

### 5.2 DocGen_SchemaService
**Type:** `with sharing`  
**Purpose:** All Salesforce schema introspection — no SOQL, only Schema.describe calls. Provides the object and field lists that power the wizard dropdowns.

- `getAllObjects()` — iterates `Schema.getGlobalDescribe()`, filters to queryable + accessible objects, sorts by label using `Comparable`
- `getFields(objectName)` — returns accessible fields with label, API name, and type
- `getRelatedObjects(objectName)` — walks the field map for REFERENCE fields (parents) and `getChildRelationships()` (children)
- `validateObjectName(name)` — regex whitelist `[a-zA-Z0-9_]+` applied before any dynamic string composition to prevent injection

---

### 5.3 DocGen_TemplateService
**Type:** `with sharing`  
**Purpose:** All operations on the template file stored in ContentVersion.

- `getTemplateText(contentVersionId)` — fetches `VersionData` as a String (supports HTML/text templates)
- `extractTokens(contentVersionId)` — calls `getTemplateText` then `parseTokens`
- `parseTokens(text)` — uses two regex patterns to extract `{{token}}` and `{{#section}}` tokens, returns deduplicated list
- `saveTemplateConfig(config)` — inserts `Document_Template__c` + child `Document_Field_Mapping__c` + `Document_Variable__c` records in one transaction
- `uploadTemplateContent(base64Content, fileName)` — decodes base64 to Blob, inserts ContentVersion, returns Id

---

### 5.4 DocGen_DataResolverService
**Type:** `with sharing`  
**Purpose:** Fetches live Salesforce record data for merge. All field names are validated through Schema.describe before being composed into SOQL strings. Uses bind variables (`:recordId`) to prevent injection.

- `resolveData(config)` — builds and executes SOQL for the primary object and any requested child/parent objects
- Reads `Max_Repeating_Rows__c` from the CMT to cap child record queries
- Returns a `ResolvedDataWrapper` with a Map of field→value for the primary record and a Map of object→List<Map> for child records

---

### 5.5 DocGen_MergeEngineService
**Type:** No sharing (no DML/SOQL — pure string processing)  
**Purpose:** Token replacement engine. Takes resolved data and the template string, produces the final merged HTML.

- `mergeTemplate(templateText, fieldData, variables, childData)` — orchestrates all steps in order
- `processVariables()` — replaces `{{sys.*}}` and other variable tokens first
- `processRepeatingSections()` — regex `{{#Section}}...{{/Section}}` blocks, iterates child record rows
- `processConditionals()` — evaluates `{{#if field}}...{{/if}}` blocks, removes block if field is blank/false
- `replaceSimpleTokens()` — replaces all remaining `{{Token}}` with resolved field values
- `applyFormat(value, directive)` — applies format directives: `date`, `currency`, `number`, `upper`, `lower`

> **Note:** The method is named `mergeTemplate` (not `merge`) because `merge` is a reserved Apex keyword.

---

### 5.6 DocGen_VariableResolverService
**Type:** `with sharing`  
**Purpose:** Resolves all system and user-defined variables into a flat String Map consumed by the merge engine.

Always auto-resolves (no configuration needed):

| Token | Source |
|---|---|
| `{{sys.today}}` | `Date.today().format()` |
| `{{sys.currentUser}}` | `UserInfo.getName()` |
| `{{sys.orgName}}` | CMT `Org_Display_Name__c`, falls back to `UserInfo.getOrganizationName()` |
| `{{sys.userEmail}}` | `UserInfo.getUserEmail()` |
| `{{sys.orgEIN}}` | CMT `Org_EIN__c` |
| `{{sys.orgAddress}}` | CMT `Org_Address__c` |
| `{{sys.orgPhone}}` | CMT `Org_Phone__c` |
| `{{sys.orgWebsite}}` | CMT `Org_Website__c` |

Also resolves `Document_Variable__c` records attached to the template: CONSTANT (static text), SYSTEM_DATE, CURRENT_USER, ORG_NAME, IMAGE (base64-embedded `<img>` tag).

---

### 5.7 DocGen_DocumentGeneratorService
**Type:** `with sharing`  
**Purpose:** Orchestrates the full generation pipeline.

- `generateHtml(config)` — calls DataResolver → VariableResolver → MergeEngine → injects print CSS → returns merged HTML string
- `generatePdf(config, linkedRecordId)` — stores merged HTML as a temporary ContentVersion, calls `new PageReference('/apex/DocGen_PdfRenderer')` with the ContentVersion Id as a URL param, calls `pr.getContentAsPDF()`, then saves the resulting Blob via FileService
- `injectPrintStyles()` — appends CSS for print layout (margins, page breaks, font sizes)

---

### 5.8 DocGen_FileService
**Type:** `with sharing`  
**Purpose:** Handles all file I/O for generated documents.

- `saveDocument(blobContent, fileName, mimeType, linkedRecordId, templateId, status, errorMsg)` — creates ContentVersion → retrieves ContentDocumentId → creates ContentDocumentLink to the linked record → inserts a Document_Generation_Log__c record
- Returns a `DocumentResponseWrapper` with the ContentDocument Id

---

### 5.9 DocGen_PdfController
**Type:** `with sharing`  
**Purpose:** Apex controller for the Visualforce PDF renderer page. Reads the `cvId` URL parameter (ContentVersion Id), fetches the HTML content, and exposes it as a `content` property for the VF page to render.

---

### 5.10 DocGen_VariableResolverService *(covered in 5.6)*

---

### 5.11 DocGen_Wrappers
**Type:** Public class (no sharing)  
**Purpose:** All shared data transfer objects used across service classes and by `@AuraEnabled` methods.

| Inner Class | Purpose |
|---|---|
| `ObjectDescribeWrapper` | Object label + API name + isCustom. Implements `Comparable` (sorts by label) |
| `FieldDescribeWrapper` | Field label + API name + type + accessibility flag |
| `TokenMappingWrapper` | Full token mapping config: token, source, type, format, repeating, etc. |
| `TemplateConfigWrapper` | Full wizard state: templateId, primaryObject, recordId, mappings, variables |
| `DocumentVariableWrapper` | Single variable definition: name, type, static value, image Id |
| `DocumentResponseWrapper` | Generation result: ContentDocument Id, base64, filename, success flag, error |

---

### 5.12 DocGen_Exception
**Type:** Public exception  
**Purpose:** Typed exception class used throughout the framework. Allows callers to distinguish DocGen errors from generic exceptions.

```apex
public class DocGen_Exception extends Exception {}
```

---

## 6. Lightning Web Components

### 6.1 docGenWizard *(Parent / Container)*
**Exposed to:** App Page, Record Page, Home Page, Tab  
**Purpose:** Root orchestrator. Owns the complete wizard state in a single `@track wizardState` object and routes rendering to the correct step component via computed boolean getters (`isStep0`–`isStep5`). Listens for `stepcomplete` and `stepback` custom events from each step child to advance or retreat the wizard.

---

### 6.2 docGenTemplateUpload *(Step 1)*
**Purpose:** File upload step. Accepts `.html` and `.txt` files using a standard `<input type="file">` element. Reads the file as base64 using the browser's `FileReader` API, calls `uploadTemplate` Apex to create a ContentVersion, then calls `extractTokens` Apex to parse `{{tokens}}` from the file. Fires `stepcomplete` with `{templateId, templateTokens}`.

> Word (.docx) files are not supported — they are binary ZIP archives that cannot be processed as plain text.

---

### 6.3 docGenObjectSelector *(Step 2)*
**Purpose:** Object selection. Uses `@wire(getObjects)` to populate the primary object combobox. On primary selection, calls `getRelatedObjects` imperatively to load the related objects dual-listbox. Fires `stepcomplete` with `{primaryObject, relatedObjects}`.

---

### 6.4 docGenFieldSelector *(Step 3)*
**Purpose:** Field selection. For each selected object (primary + related), calls `getFields` imperatively in `connectedCallback`, then renders a `docGenFieldPickerDual` per object. Fires `stepcomplete` with `{selectedFields: { ObjectApiName: [fieldApiNames] }}`.

---

### 6.5 docGenMappingBuilder *(Step 4)*
**Purpose:** Token-to-field mapping. Renders one row per extracted token. Each row has: Mapping Type selector (FIELD / CONSTANT / VARIABLE / EXPRESSION), Object selector, Field selector (reloads on object change), Format Override input, Static Value input (shown for CONSTANT), and Is Repeating toggle. Fires `stepcomplete` with `{tokenMappings: [...]}`.

---

### 6.6 docGenVariablesPanel *(Step 5)*
**Purpose:** Variables and constants. Pre-populates the four system variables (sys.today, sys.currentUser, sys.orgName, sys.userEmail) as read-only rows. Allows users to add custom CONSTANT variables with free-text name + value. Fires `stepcomplete` with `{variables: [...]}`.

---

### 6.7 docGenPreviewDownload *(Step 6)*
**Purpose:** Preview and output. Calls `generatePreview` Apex and renders the merged HTML using `lightning-formatted-rich-text` (iframe is blocked in LWC by the platform's Content Security Policy). Provides three action buttons:
- **Save Configuration** — calls `saveTemplateConfig` Apex to persist the template record
- **Download as PDF** — calls `generateDocument` with `format='PDF'`, then triggers a browser download using `atob()` → `Blob` → object URL → anchor click
- **Download as Word** — same flow with `format='WORD'`, saves as `.html` with a `.docx` extension (Word opens HTML natively)

---

### 6.8 docGenProgressBar *(Utility)*
**Purpose:** Visual step indicator at the top of the wizard. Accepts `@api steps` (array of step labels) and `@api currentStep` (index). Computes CSS classes and a percentage width for the progress fill bar.

---

### 6.9 docGenTokenBadge *(Utility)*
**Purpose:** Renders a single token as a styled chip/badge with monospace font. Used in the mapping builder and preview steps to display token names clearly. Accepts `@api token`.

---

### 6.10 docGenErrorPanel *(Utility)*
**Purpose:** Standardised error display. Accepts `@api errors` and handles three formats: plain string, AuraHandledException object (`.body.message`), and arrays of errors. Used in every step component.

---

### 6.11 docGenFieldPickerDual *(Utility)*
**Purpose:** Reusable dual-listbox wrapper for selecting fields from a single object. Accepts `@api objectName` and `@api fields` (list of FieldDescribeWrapper). Fires a `fieldselectionchanged` event with `{objectName, selectedFields}` when the selection changes.

---

## 7. Visualforce Page

### DocGen_PdfRenderer
**Controller:** `DocGen_PdfController`  
**Purpose:** Renders the merged HTML as a full page with no Salesforce chrome (`showHeader=false`, `sidebar=false`). The `getContentAsPDF()` method on a `PageReference` pointing to this page is how Apex generates a PDF from HTML — Salesforce's native rendering engine converts the page output to a PDF binary.

The page renders `{!content}` with `escape="false"` so the full HTML (including inline styles and tables) is output verbatim.

---

## 8. App, Tabs & Navigation

### Lightning Console App — DocGen Document Generator

**App API Name:** `DocGen_Document_Generator`  
**Type:** Lightning Console (`navType=Console`, `uiType=Lightning`)  
**Header Colour:** `#032D60` (Salesforce Navy)  
**Purpose:** Dedicated workspace for the document generation tooling, separate from the main Nonprofit org navigation.

**Tabs included:**

| Tab | Type | Purpose |
|---|---|---|
| Home | Standard (`standard-home`) | Loads the DocGen Template Builder home page with the wizard |
| Document Templates | Custom Object Tab | List/detail view for `Document_Template__c` |
| Field Mappings | Custom Object Tab | List/detail view for `Document_Field_Mapping__c` |
| Variables | Custom Object Tab | List/detail view for `Document_Variable__c` |
| Generation Logs | Custom Object Tab | Audit log of all generated documents |
| Reports | Standard | Standard Salesforce Reports tab |

**Home Page Override:**  
The app's `profileActionOverrides` point the `standard-home` tab to `DocGen_Template_Builder_Home` FlexiPage for both the Admin and Standard profiles, so the wizard loads automatically when users open the app.

### Custom Tabs

Four custom object tabs were created to surface each DocGen object in the app navigation:

| Tab File | Motif |
|---|---|
| `Document_Template__c.tab-meta.xml` | Custom13: Box |
| `Document_Field_Mapping__c.tab-meta.xml` | Custom13: Box |
| `Document_Variable__c.tab-meta.xml` | Custom13: Box |
| `Document_Generation_Log__c.tab-meta.xml` | Custom13: Box |

### Home FlexiPage — DocGen Template Builder Home

**Type:** HomePage  
**Template:** `home:desktopTemplateHeaderThreeColumns`  
**Purpose:** Hosts the `docGenWizard` component in the top region. Activated as the home tab for the DocGen app via the app's `profileActionOverrides`.

---

## 9. Permission Set

### DocGen Full Access

**API Name:** `DocGen_Full_Access`  
**Assigned to:** All active System Administrator users (assigned via anonymous Apex on first deploy)  
**Purpose:** Grants the minimum permissions required to use all DocGen functionality.

**What it grants:**

| Category | Detail |
|---|---|
| Object Permissions | Create, Read, Edit, Delete, View All, Modify All on all 4 DocGen objects |
| Field Permissions | Read + Edit on all custom fields (excluding required fields, which are open by default) |
| Apex Class Access | All 11 `DocGen_*` Apex classes |
| Visualforce Page | `DocGen_PdfRenderer` |
| Tab Visibility | All 4 custom object tabs set to Visible |
| App Visibility | `DocGen_Document_Generator` app |
| User Permission | `ContentWorkspaces` — required for creating and accessing Salesforce Files |

> **Required fields** (`Token_Name__c`, `Primary_Object__c`, `Variable_Type__c`) do not need explicit FLS in a permission set — they are always open when the user has object access.

---

## 10. Sample Template

**File:** `docs/sample_donation_acknowledgment.html`  
**Purpose:** Ready-to-upload HTML template demonstrating all DocGen features for a nonprofit donation acknowledgment letter.

**Features demonstrated:**

| Feature | Example |
|---|---|
| System variable | `{{sys.today}}`, `{{sys.orgName}}`, `{{sys.currentUser}}`, `{{sys.userEmail}}` |
| Config variable | `{{sys.orgEIN}}`, `{{sys.orgAddress}}`, `{{sys.orgPhone}}`, `{{sys.orgWebsite}}` |
| Field token | `{{DonorName}}`, `{{DonorMailingCity}}`, `{{TotalGiftAmount}}` |
| Repeating section | `{{#DonationItems}}...{{/DonationItems}}` — one table row per donation |
| Conditional block | `{{#if IsMajorDonor}}...{{/if}}` — major donor paragraph shown conditionally |

**Suggested primary object:** `Contact` or `Opportunity`

---

## 11. Token Reference

### System Variables (auto-resolved, no mapping needed)

| Token | Value |
|---|---|
| `{{sys.today}}` | Today's date in the configured format |
| `{{sys.currentUser}}` | Full name of the logged-in user |
| `{{sys.userEmail}}` | Email address of the logged-in user |
| `{{sys.orgName}}` | Org display name from DocGen Config CMT |
| `{{sys.orgEIN}}` | Org EIN from DocGen Config CMT |
| `{{sys.orgAddress}}` | Org mailing address from DocGen Config CMT |
| `{{sys.orgPhone}}` | Org phone from DocGen Config CMT |
| `{{sys.orgWebsite}}` | Org website from DocGen Config CMT |

### Field Tokens

Format: `{{AnyName}}` — mapped to a Salesforce field in Step 4 of the wizard.

### Repeating Sections

```
{{#SectionName}}
  {{FieldInsideSection}}
{{/SectionName}}
```

The section name must be mapped to a child object in Step 4 with **Is Repeating Section** checked.

### Conditional Blocks

```
{{#if FieldName}}
  Content shown only when FieldName is non-blank/non-false
{{/if}}
```

### Format Directives

Set in the **Format Override** field during mapping:

| Directive | Effect |
|---|---|
| `date` | Formats as date using `Default_Date_Format__c` from CMT |
| `currency` | Formats with `$` prefix and 2 decimal places |
| `number` | Formats as a number with commas |
| `upper` | Converts to UPPERCASE |
| `lower` | Converts to lowercase |

---

## 12. End-to-End Usage Guide

### Step 1 — Open the App
Navigate to the **DocGen Document Generator** app from the App Launcher. The wizard loads automatically on the Home tab.

### Step 2 — Upload Template (Wizard Step 1)
Click **Choose File**, select the HTML template (e.g. `sample_donation_acknowledgment.html`), then click **Upload & Extract Tokens**. The system uploads the file and scans it for `{{tokens}}`. You will see the list of detected tokens before moving on.

### Step 3 — Select Objects (Wizard Step 2)
Choose the **Primary Object** — the Salesforce object whose record will drive the document (e.g. Contact, Opportunity). Optionally select **Related Objects** to make parent/child fields available for mapping.

### Step 4 — Select Fields (Wizard Step 3)
For each selected object, choose which fields you want to be available in the mapping step. Only selected fields are queried at runtime.

### Step 5 — Map Tokens (Wizard Step 4)
For each token extracted from the template, choose:
- **Mapping Type:** FIELD (from Salesforce), CONSTANT (fixed text), VARIABLE, or EXPRESSION
- **Source Object + Field:** which field's value replaces the token
- **Format Override:** optional formatting
- **Is Repeating Section:** check this for tokens that are section headers (`{{#SectionName}}`)

System tokens (`{{sys.*}}`) do not need to be mapped — they are skipped automatically.

### Step 6 — Variables (Wizard Step 5)
Review the pre-populated system variables. Add any custom CONSTANT variables (e.g. a fixed disclaimer text) that are referenced in the template.

### Step 7 — Preview & Download (Wizard Step 6)
Click **Generate Preview** to see the merged document inline. Then:
- **Save Configuration** — saves the template + mapping as records for future use
- **Download as PDF** — generates a PDF and saves it to Salesforce Files
- **Download as Word** — generates an HTML file with .docx extension (opens in Word)

The generated file is also automatically attached to the linked record as a Salesforce File and logged in `Document_Generation_Log__c`.

---

## 13. Folder Structure

```
force-app/main/default/
├── applications/
│   └── DocGen_Document_Generator.app-meta.xml
├── classes/
│   ├── DocGen_Controller.cls
│   ├── DocGen_DataResolverService.cls
│   ├── DocGen_DocumentGeneratorService.cls
│   ├── DocGen_Exception.cls
│   ├── DocGen_FileService.cls
│   ├── DocGen_MergeEngineService.cls
│   ├── DocGen_PdfController.cls
│   ├── DocGen_SchemaService.cls
│   ├── DocGen_TemplateService.cls
│   ├── DocGen_VariableResolverService.cls
│   └── DocGen_Wrappers.cls
├── customMetadata/
│   └── DocGen_Config__mdt.Default.md-meta.xml
├── flexipages/
│   └── DocGen_Template_Builder_Home.flexipage-meta.xml
├── lwc/
│   ├── docGenWizard/
│   ├── docGenTemplateUpload/
│   ├── docGenObjectSelector/
│   ├── docGenFieldSelector/
│   ├── docGenMappingBuilder/
│   ├── docGenVariablesPanel/
│   ├── docGenPreviewDownload/
│   ├── docGenProgressBar/
│   ├── docGenTokenBadge/
│   ├── docGenErrorPanel/
│   └── docGenFieldPickerDual/
├── objects/
│   ├── Document_Template__c/
│   ├── Document_Field_Mapping__c/
│   ├── Document_Variable__c/
│   ├── Document_Generation_Log__c/
│   └── DocGen_Config__mdt/
├── pages/
│   └── DocGen_PdfRenderer.page
├── permissionsets/
│   └── DocGen_Full_Access.permissionset-meta.xml
└── tabs/
    ├── Document_Template__c.tab-meta.xml
    ├── Document_Field_Mapping__c.tab-meta.xml
    ├── Document_Variable__c.tab-meta.xml
    └── Document_Generation_Log__c.tab-meta.xml

docs/
├── DocGen_Complete_Reference.md       ← this document
└── sample_donation_acknowledgment.html
```

---

*Document Generator (DocGen) · nonprofit-demo-org-1 · Built April 2026*
