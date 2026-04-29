# DocGen — Developer Guide

**Document Generation System for Salesforce**  
**Version:** 1.1 | **Updated:** April 2026  
**Org:** nonprofit-demo-org-1 (`spant-9csk@force.com` · https://techpulse5.my.salesforce.com)  
**API Version:** 66.0

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Data Model](#2-data-model)
3. [Custom Metadata](#3-custom-metadata)
4. [Apex Classes](#4-apex-classes)
5. [Lightning Web Components](#5-lightning-web-components)
6. [Visualforce Pages](#6-visualforce-pages)
7. [Token Processing Pipeline](#7-token-processing-pipeline)
8. [End-to-End Data Flow](#8-end-to-end-data-flow)
9. [Record Page Integration & Navigation Flow](#9-record-page-integration--navigation-flow)
10. [Security Model](#10-security-model)
11. [Deployment Guide](#11-deployment-guide)
12. [Extensibility](#12-extensibility)
13. [Known Constraints & Design Decisions](#13-known-constraints--design-decisions)

---

## 1. Architecture Overview

DocGen is a layered system with four tiers:

```
┌─────────────────────────────────────────────────────────────────────┐
│                     LWC Wizard — Browser (Step 0–4)                 │
│  docGenWizard → docGenTemplateUpload → docGenObjectSelector          │
│              → docGenMappingBuilder → docGenVariablesPanel           │
│              → docGenPreviewDownload                                 │
└────────────────────────────┬────────────────────────────────────────┘
                             │ @AuraEnabled Apex calls (JSON payloads)
┌────────────────────────────▼────────────────────────────────────────┐
│                      DocGen_Controller.cls                           │
│  (Single entry point — thin facade, delegates to services)           │
└───┬──────────┬──────────┬──────────┬──────────┬──────────┬──────────┘
    │          │          │          │          │          │
    ▼          ▼          ▼          ▼          ▼          ▼
Schema    Template   DataResolver  MergeEngine  Variable   FileService
Service   Service               Service     Resolver    Service
    │          │                                             │
    │       ContentVersion                             ContentVersion
    │       (template blob)                            (output file)
    │
    ▼
DocGen_HtmlViewerController  ← Visualforce page (DocGen_HtmlViewer.page)
  reads preview ContentVersion                  (preview & PDF render)
```

### Key Design Principles

1. **No managed packages.** Everything is native Apex + LWC + standard platform objects.
2. **Controller is a thin facade.** All business logic lives in service classes (`DocGen_*Service.cls`). The controller only wraps calls with `AuraHandledException` and deserializes JSON.
3. **LWS-safe preview.** Lightning Web Security blocks `iframe.srcdoc` and `new Blob([...], {type:'text/html'})`. Preview is rendered via a Visualforce page URL (`/apex/DocGen_HtmlViewer?cvId=...`) that reads a ContentVersion and renders its content — no Blob, no srcdoc.
4. **Template tokens are canonical.** The mapping builder always iterates `templateTokens` (from the upload step) as the authoritative list. `savedMappings` only supplies pre-filled values for tokens that still exist — it never replaces the canonical token list.
5. **FLS/CRUD enforced everywhere.** All SOQL uses `WITH SECURITY_ENFORCED`. All DML checks `isCreateable()` before inserting. The schema service filters fields by `isAccessible()`.

---

## 2. Data Model

### `Document_Template__c` — Template Registry

Stores the definition of a saved document template.

| Field | Type | Description |
|---|---|---|
| `Name` (auto) | Text | Auto-generated record name |
| `Primary_Object__c` | Text(255) | API name of the primary SObject |
| `Template_Content_Version_Id__c` | Text(18) | ContentVersion ID of the uploaded HTML file |
| `Status__c` | Picklist | `Active` / `Inactive` |
| `Version__c` | Number | Integer version counter (starts at 1) |
| `Is_Active__c` | Checkbox | Used to filter active templates in queries |
| `Description__c` | Long Text Area | Optional description |
| `Language__c` | Text | Optional language tag |

Child relationships: `Document_Field_Mapping__c` (mappings), `Document_Variable__c` (variables), `Document_Generation_Log__c` (generation history).

---

### `Document_Field_Mapping__c` — Token Mappings

One record per token per template. Stores the full mapping definition.

| Field | Type | Description |
|---|---|---|
| `Template__c` | Lookup(Document_Template__c) | Parent template |
| `Token_Name__c` | Text(255) | Full token string, e.g., `{{DonorName}}` |
| `Source_Object__c` | Text(255) | Object API name the field comes from |
| `Source_Field__c` | Text(255) | Field API name |
| `Relationship_Path__c` | Text(255) | Traversal path for parent fields, e.g., `Account.Name` |
| `Mapping_Type__c` | Picklist | `FIELD` / `CONSTANT` / `VARIABLE` |
| `Static_Value__c` | Long Text Area | Value when Mapping Type = CONSTANT |
| `Format_Override__c` | Text(255) | Format directive, e.g., `currency`, `date:MM/dd/yyyy` |
| `Is_Repeating_Section__c` | Checkbox | True for tokens inside a repeating section |
| `Repeat_Object__c` | Text(255) | Child object API name for repeating section tokens |

---

### `Document_Variable__c` — Document Variables

Custom variables injected per template generation. Currently surfaced in Step 4 (Variables) of the wizard.

| Field | Type | Description |
|---|---|---|
| `Template__c` | Lookup(Document_Template__c) | Parent template |
| `Name` | Text | Variable name (used as token key) |
| `Variable_Type__c` | Picklist | `CONSTANT` / `SYSTEM_DATE` / `CURRENT_USER` / `ORG_NAME` / `IMAGE` |
| `Static_Value__c` | Long Text Area | Value for CONSTANT type |
| `Image_Content_Version_Id__c` | Text(18) | ContentVersion ID for IMAGE type |

---

### `Document_Generation_Log__c` — Audit Log

One record created for every document generation attempt (success or failure).

| Field | Type | Description |
|---|---|---|
| `Template__c` | Lookup(Document_Template__c) | Template used (nullable if config-only) |
| `Record_Id__c` | Text(18) | Source record ID |
| `Generated_At__c` | DateTime | Timestamp of the generation attempt |
| `Status__c` | Picklist | `Success` / `Failed` |
| `Output_Content_Document_Id__c` | Text(18) | ContentDocumentId of the generated file |
| `Error_Message__c` | Long Text Area | Error detail on failure |

---

## 3. Custom Metadata

### `DocGen_Config__mdt` — Org-Level Configuration

Single record with `DeveloperName = Default` configures system variables and runtime limits.

| Field | Description |
|---|---|
| `Org_Display_Name__c` | Overrides `sys.orgName` (defaults to Salesforce org name if blank) |
| `Org_EIN__c` | Federal tax ID for `{{sys.orgEIN}}` |
| `Org_Address__c` | Address for `{{sys.orgAddress}}` |
| `Org_Phone__c` | Phone for `{{sys.orgPhone}}` |
| `Org_Website__c` | Website URL for `{{sys.orgWebsite}}` |
| `Max_Repeating_Rows__c` | SOQL LIMIT for child record queries (default: 200) |

This record is read in `DocGen_VariableResolverService.resolve()` and `DocGen_DataResolverService.resolveData()`.

---

## 4. Apex Classes

### `DocGen_Controller.cls` — `public with sharing`

The single `@AuraEnabled` entry point for all LWC callouts. Deserializes JSON payloads and delegates to service classes. Every method wraps exceptions in `AuraHandledException`.

| Method | Cacheable | Delegates To |
|---|---|---|
| `searchObjects(String searchTerm)` | Yes | `DocGen_SchemaService.searchObjects` |
| `getFields(String objectName)` | Yes | `DocGen_SchemaService.getFields` |
| `getRelatedObjects(String objectName)` | Yes | `DocGen_SchemaService.getRelatedObjects` |
| `extractTokens(String contentVersionId)` | No | `DocGen_TemplateService.extractTokens` |
| `uploadTemplate(String base64Content, String fileName)` | No | `DocGen_TemplateService.uploadTemplateContent` |
| `saveTemplateConfig(String configJson)` | No | `DocGen_TemplateService.saveTemplateConfig` |
| `storePreviewHtml(String htmlContent)` | No | Inline ContentVersion insert |
| `generatePreview(String configJson)` | No | `DocGen_DocumentGeneratorService.generateHtml` |
| `generateDocument(String configJson, String format, String linkedRecordId)` | No | `DocGen_DocumentGeneratorService.generateHtml/generatePdf` + `DocGen_FileService.saveDocument` |
| `getTemplates()` | No | Inline SOQL on `Document_Template__c` |

**`storePreviewHtml`** creates a temporary ContentVersion (`IsMajorVersion = false`) containing the merged HTML. The ContentVersion ID is returned to the LWC, which constructs the VF page URL `/apex/DocGen_HtmlViewer?cvId=...` for the iframe `src`.

---

### `DocGen_SchemaService.cls` — `public with sharing`

Handles all Salesforce schema introspection without using SOQL on EntityDefinition (which caused internal server errors in some orgs).

**`searchObjects(String searchTerm)`**  
Two-step approach:
1. Filter `Schema.getGlobalDescribe()` keys with `key.contains(lower)` — cheap string operation, no SOQL
2. Call `getDescribe()` only on matched candidates (capped at 30 results)
3. Skip internal object suffixes: `share`, `history`, `feed`, `tag`, `changeevent`, `votestat`, `viewstat`
4. Filter by `isQueryable()`, `isAccessible()`, non-blank label

**`getFields(String objectName)`**  
Returns all `isAccessible()` fields via `SObjectType.getDescribe().fields.getMap()`.

**`getRelatedObjects(String objectName)`**  
Introspects lookup fields on the object to find parent objects, and `getChildRelationships()` to find child objects.

**`validateObjectName(String name)`**  
Pattern-matches against `[a-zA-Z0-9_]+` — prevents SOQL injection in dynamic queries that use the object name.

---

### `DocGen_TemplateService.cls` — `public with sharing`

Manages template file storage and token extraction.

**`uploadTemplateContent(String base64Content, String fileName)`**  
Decodes base64, creates a `ContentVersion`, returns the ContentVersion ID.

**`extractTokens(String contentVersionId)`**  
Reads the ContentVersion blob as text, calls `parseTokens`.

**`parseTokens(String text)`**  
Two-pass regex extraction:
- Pass 1: `\{\{#([^{}]*)\}\}` — section open markers, excluding `{{#if ...}}`
- Pass 2: `\{\{([^{}#/][^{}]*)\}\}` — plain field tokens, excluding `sys.*`
- Deduplication via `Set<String>`
- Final `result.sort()` for deterministic ordering

**`saveTemplateConfig(DocGen_Wrappers.TemplateConfigWrapper config)`**  
Inserts `Document_Template__c`, then bulk-inserts `Document_Field_Mapping__c` and `Document_Variable__c` child records. Checks `isCreateable()` before each DML.

---

### `DocGen_DocumentGeneratorService.cls` — `public with sharing`

Orchestrates the full document generation pipeline.

**`generateHtml(TemplateConfigWrapper config)`**  
Sequence:
1. `DocGen_TemplateService.getTemplateText(config.templateId)` — fetch raw HTML
2. `DocGen_VariableResolverService.resolve(config.variables)` — build system + custom variable map
3. `DocGen_DataResolverService.resolveData(config.recordId, config.primaryObject, config.tokenMappings)` — SOQL for primary and child records
4. `DocGen_MergeEngineService.mergeTemplate(...)` — perform token replacement

**`generatePdf(String mergedHtml)`**  
- Stores `mergedHtml` in a temp ContentVersion
- Uses `PageReference('/apex/DocGen_PdfRenderer').getContentAsPDF()` to render
- Returns the PDF `Blob`

> **Note:** `generatePdf` is a server-side PDF render path used when `generateDocument` is called with `format = 'PDF'`. The wizard's "Open as PDF" button uses a different approach: it opens the preview ContentVersion directly via the VF viewer URL, letting the user print-to-PDF from the browser.

---

### `DocGen_DataResolverService.cls` — `public with sharing`

Queries live record data for the merge engine.

**`resolveData(String recordId, String primaryObject, List<TokenMappingWrapper> mappings)`**  
1. Groups requested fields by object using `groupFieldsByObject` — parent traversal paths (e.g., `Account.Name`) are added to the primary object's field set, not the parent's
2. Builds a validated field list via `buildFieldList` — checks FLS (`isAccessible()`) for each field
3. Executes dynamic SOQL for the primary record with `WITH SECURITY_ENFORCED`
4. For each repeating section mapping, validates the lookup relationship with `getParentLookupField`, queries child records up to `Max_Repeating_Rows__c`
5. Returns `ResolvedDataWrapper` with `primaryRecord` (flat Map) and `childRecords` (Map of section name → List of flat Maps)

**`flattenRecord(SObject rec)`**  
Recursively flattens nested SObjects (e.g., `Account.Name`) into dot-notation keys (e.g., `Account.Name` → value) for merge lookup.

**`validateTraversalPath(String rootObject, String path)`**  
Walks a dot-notation path through schema descriptors to confirm each segment is an accessible REFERENCE field — prevents arbitrary SOQL injection via relationship traversal.

---

### `DocGen_MergeEngineService.cls` — `public class` (no sharing)

Performs all token replacement. Does not execute SOQL — operates on pre-resolved data maps.

**`mergeTemplate(...)`**  
Execution order:
1. System/custom variables: `result.replace('{{varName}}', value)` — handles both `{{varName}}` and `{{sys.varName}}` forms
2. `processRepeatingSections` — expands `{{#Name}}...{{/Name}}` blocks using child data rows
3. `processConditionals` — evaluates `{{#if Field}}...{{/if}}` blocks against primary data
4. Primary + parent field tokens — replaces all non-repeating `{{token}}` placeholders

**`applyFormat(String rawValue, String formatOverride)`**  
Supported format types: `date` (Java `Datetime.format` pattern), `currency` (`$` + 2 decimal places), `number` (configurable decimal scale), `upper`, `lower`.

**`processRepeatingSections`**  
Uses regex `\{\{#([a-zA-Z0-9_]+)\}\}([\s\S]*?)\{\{/\1\}\}` — lazy match so adjacent sections don't bleed. Collects replacements as pairs, applies them after the match loop (avoids modifying the string during iteration).

**`isTruthy(Object val)`**  
Returns false for `null`, `false`, `0`, empty string, `'null'` — all other values are considered truthy.

---

### `DocGen_VariableResolverService.cls` — `public with sharing`

Builds the variable resolution map used before field token replacement.

**`resolve(List<DocumentVariableWrapper> variables)`**  
Always sets these system variables from `UserInfo`:
- `today`, `currentUser`, `orgName`, `userEmail`

Then reads `DocGen_Config__mdt.Default` to override/add:
- `orgName` (if `Org_Display_Name__c` is set), `orgEIN`, `orgAddress`, `orgPhone`, `orgWebsite`

Then processes the `variables` list by type:
- `CONSTANT` → static value
- `SYSTEM_DATE` → `Date.today().format()`
- `CURRENT_USER` → `UserInfo.getName()`
- `ORG_NAME` → `UserInfo.getOrganizationName()`
- `IMAGE` → inline base64 `<img>` tag via `resolveImageToken`

**`resolveImageToken(String versionId)`**  
Reads ContentVersion, base64-encodes the blob, returns `<img src="data:image/xxx;base64,..."/>` string. Inserted inline in the HTML — works in PDF output without external image URLs.

---

### `DocGen_FileService.cls` — `public with sharing`

Handles output file storage and logging.

**`saveDocument(Blob content, String fileName, String linkedRecordId, String templateId)`**  
1. Creates `ContentVersion` (IsMajorVersion = true)
2. Re-queries for `ContentDocumentId`
3. If `linkedRecordId` is provided, creates `ContentDocumentLink` with `ShareType = 'V'`, `Visibility = 'AllUsers'`
4. Creates `Document_Generation_Log__c` entry (success or failure)
5. Returns `DocumentResponseWrapper` with base64 content for browser download trigger

---

### `DocGen_HtmlViewerController.cls` — `public without sharing`

Visualforce controller for `DocGen_HtmlViewer.page`. Uses `without sharing` because preview ContentVersions are not owned by the running user.

**Constructor**  
Reads `cvId` URL parameter → queries ContentVersion → calls `extractBodyContent`.

**`extractBodyContent(String html)`**  
Critical for correct rendering. The VF page emits its own HTML wrapper. If the template's full HTML document is injected as-is, the browser encounters a nested `<html><head>...</head><body>` which causes HTML5 parse errors:
- Inner `<head>` tag in "in body" insertion mode is silently dropped
- CSS inside the inner `<head>` loses scope
- Layout collapses

Fix: extract all `<style>` blocks and the `<body>` inner content, discard the outer `<html>`, `<head>`, `<body>` wrappers. Return `styles + bodyContent` — VF injects this cleanly into its own body.

---

### `DocGen_Wrappers.cls` — `public class`

Data Transfer Objects (DTOs) annotated with `@AuraEnabled` for LWC serialization.

| Class | Purpose |
|---|---|
| `ObjectDescribeWrapper` | Object API name, label, isCustom. Implements `Comparable` (sorts by label) |
| `FieldDescribeWrapper` | Field API name, label, fieldType, isAccessible |
| `TokenMappingWrapper` | Full token mapping definition (token, sourceObject, sourceField, relationshipPath, mappingType, staticValue, formatOverride, isRepeating, repeatObject) |
| `TemplateConfigWrapper` | Full document generation config (templateId, primaryObject, recordId, tokenMappings, variables) |
| `DocumentVariableWrapper` | Variable definition (variableName, variableType, staticValue, imageVersionId, expression) |
| `DocumentResponseWrapper` | Generation result (contentDocumentId, base64Content, fileName, success, errorMessage) |
| `TemplateSaveResultWrapper` | Template save result (templateId, templateName) |

---

### `DocGen_Exception.cls`

Simple custom exception class for typed error propagation throughout the service layer.

```apex
public class DocGen_Exception extends Exception {}
```

---

## 5. Lightning Web Components

### `docGenWizard` — Orchestrator

**Purpose:** Top-level wizard container. Manages step progression and shared state across all steps.

**State management:**  
`@track wizardState` is a flat object persisted to `sessionStorage` under the key `docgen_wizard_state`. On `connectedCallback`, it deserializes the session and migrates old sessions that used the flat `relatedObjectsWithLabels` shape instead of the `parentObjects` / `childObjects` split.

**Step progression:**  
Each child component fires `stepcomplete` (bubbling, composed). `handleStepComplete` merges `evt.detail` into `wizardState`. On Step 0 completion with a new `templateId`, `tokenMappings` is cleared to prevent stale mappings from a prior template.

**Props passed to children:**

| Component | Props |
|---|---|
| `docGenObjectSelector` | `templateTokens`, `savedPrimaryObject`, `savedPrimaryLabel`, `savedParentObjects`, `savedChildObjects` |
| `docGenMappingBuilder` | `templateTokens`, `primaryObject`, `parentObjects`, `childObjects`, `savedMappings` |
| `docGenPreviewDownload` | `templateConfig` (object with templateId, primaryObject, tokenMappings, variables, recordId) |

---

### `docGenTemplateUpload` — Step 0

**Purpose:** File picker that uploads an HTML template to Salesforce and extracts its merge tokens.

**Flow:**
1. `handleFileSelected` reads the file as base64 via `FileReader.readAsDataURL` (strips the `data:...;base64,` prefix)
2. Calls `uploadTemplate` Apex → receives ContentVersion ID
3. Calls `extractTokens` Apex → receives sorted token list
4. Fires `stepcomplete` with `{ templateId, templateTokens }`

---

### `docGenObjectSelector` — Step 1

**Purpose:** Object search and selection for primary, parent, and child objects.

**Search mechanism:**  
No debounce. User types term → clicks **Search** button (or presses Enter) → `_triggerSearch()` reads the input value imperatively via `this.template.querySelector('.search-input').value`. Calls `searchObjects` Apex.

Already-selected objects are filtered from results using a `Set` of taken API names.

**Child object validation (`_validateChildObjects`):**  
Extracts section names from `templateTokens` by filtering tokens that start with `{{#` and do NOT start with `{{#if `. Compares child object API names against section names (case-insensitive). Sets `childWarning` if any child has no matching section marker.

**`handleClearAll()`:** Resets primary, parents, children, suggestions, warning, and mode in a single operation.

**Events fired:** `stepcomplete` with `{ primaryObject, primaryObjectLabel, parentObjects, childObjects, relatedObjects, relatedObjectsWithLabels }`

---

### `docGenMappingBuilder` — Step 2

**Purpose:** Maps each template token to a Salesforce field, constant, or variable.

**Token initialization (`connectedCallback`):**  
1. `preloadFields` — fetches field lists for all objects in parallel (stored in `@track fieldCache`)
2. Builds `savedByToken` map from `savedMappings`
3. Iterates `templateTokens` (canonical list). For each token:
   - If found in `savedByToken`: restores saved mapping, refreshes `fieldOptions`, `isFieldType`, `isConstantType`, `isParentType`
   - Otherwise: calls `_buildFreshMapping(token)`

**`_buildFreshMapping(token)`:**  
- Detects `{{#...}}` section tokens → pre-sets `isRepeating = true`, `repeatObject` = matched child API name, `sourceObject` = child API name
- Plain tokens → `sourceObject = primaryObject`, `isRepeating = false`

**`handleMappingChange(evt)`:**  
Reads `data-token` and `data-field` from the event target. On `sourceObject` change: fetches fields, updates `fieldOptions`, resets `sourceField`/`relationshipPath`, updates `isParentType`/`isRepeating`. On `sourceField` change for parent type: auto-sets `relationshipPath = sourceObject.sourceField`. On `mappingType` change: updates `isFieldType`/`isConstantType`.

**Events fired:** `stepcomplete` with `{ tokenMappings: [...] }` — serializes only the data fields (strips UI-only fields like `fieldOptions`, `isFieldType`, etc.)

---

### `docGenVariablesPanel` — Step 3

**Purpose:** Informational display of system variables. In the current implementation, fires `stepcomplete` with `{ variables: [] }`. Custom variable authoring UI (Step 4) is scaffolded for future extension.

---

### `docGenPreviewDownload` — Step 4

**Purpose:** Preview and download the generated document.

**Preview flow:**
1. `handleGeneratePreview` calls `generatePreview` Apex → receives merged HTML string
2. Calls `storePreviewHtml` Apex → stores as ContentVersion, receives ContentVersion ID
3. `previewSrc` getter returns `/apex/DocGen_HtmlViewer?cvId=${this.previewCvId}`
4. `<iframe src={previewSrc}>` renders the VF page in-frame

**PDF flow:**  
`handleDownloadPdf` calls `window.open('/apex/DocGen_HtmlViewer?cvId=...', '_blank')` — opens the VF page in a new tab. User prints to PDF using browser print dialog.

> This approach avoids all LWS restrictions: no `Blob({type:'text/html'})`, no `iframe.srcdoc`, no blob URLs.

**Word download / Save to Files:**  
`_downloadDocument(format, mimeType)` calls `generateDocument` Apex. On success, `_triggerBrowserDownload` decodes base64, creates a binary Blob (non-HTML MIME types are allowed by LWS), and triggers `<a download>` click. The file is also stored in Salesforce Files linked to the provided Record ID.

**Save template:**  
`handleSaveConfig` calls `saveTemplateConfig` Apex with the full wizard `templateConfig`. On success, displays a sticky toast and enables the **View Template Record** navigation button.

---

### `docGenProgressBar` — Utility

Displays the step progress indicator at the top of the wizard. Accepts step labels and current step index.

---

### `docGenErrorPanel` — Utility

Displays Apex `AuraHandledException` messages. Accepts an `error` object and extracts `body.message` or `detail` for display.

---

### `docGenTokenBadge` — Utility

Renders a single token as a styled pill/badge. Used in the token list display in Step 0 and Step 2.

---

### `docGenFieldSelector` — Utility

Combobox wrapper for field selection. Renders a `lightning-combobox` with options built from `FieldDescribeWrapper` objects.

---

### `docGenFieldPickerDual` — Utility

Dual-list or multi-select field picker. Available for advanced field selection scenarios.

---

## 6. Visualforce Pages

### `DocGen_HtmlViewer.page`

```xml
<apex:page
    controller="DocGen_HtmlViewerController"
    sidebar="false"
    showHeader="false"
    standardStylesheets="false">
    <apex:outputText value="{!htmlContent}" escape="false"/>
</apex:page>
```

**Purpose:** Renders merged HTML for inline preview (iframe) and PDF printing.

**Key decisions:**
- No `docType` attribute — this is intentional. Adding `docType="html-5.0"` causes VF to emit a full `<!DOCTYPE html><html><head>...</head><body>` wrapper. When the template's own HTML is injected inside, the browser encounters a nested `<head>` in "in body" mode, silently drops it per the HTML5 spec, and the template CSS loses scope. Without `docType`, VF emits a simpler wrapper that doesn't conflict.
- `standardStylesheets="false"` — prevents Salesforce's default styles from leaking into the rendered document
- `sidebar="false"` and `showHeader="false"` — full-page render, no Salesforce chrome
- `escape="false"` — required for raw HTML output; the content is org-generated (not user input), so XSS risk is managed at the Apex tier

**Access URL:** `/apex/DocGen_HtmlViewer?cvId={ContentVersionId}`

---

## 7. Token Processing Pipeline

### Step 1: Extraction (`DocGen_TemplateService.parseTokens`)

```
Template HTML
    │
    ├─ Pass 1: Regex \{\{#([^{}]*)\}\}
    │    Match: {{#SectionName}}
    │    Exclude: {{#if ...}}
    │    Result: section open markers (e.g., {{#OpportunityLineItem}})
    │
    ├─ Pass 2: Regex \{\{([^{}#/][^{}]*)\}\}
    │    Match: {{FieldToken}}
    │    Exclude: sys.* tokens
    │    Result: field tokens (e.g., {{DonorName}})
    │
    ├─ Deduplication via Set<String>
    └─ result.sort() → deterministic alphabetical order
```

### Step 2: Mapping Storage

The user maps each token in the LWC. On `handleNext` in `docGenMappingBuilder`, `tokenMappings` is serialized (stripping UI fields) and passed via `stepcomplete` event → stored in `wizardState.tokenMappings` → persisted to `sessionStorage`.

On `saveTemplateConfig`, each mapping becomes a `Document_Field_Mapping__c` record.

### Step 3: Data Resolution (`DocGen_DataResolverService.resolveData`)

```
TokenMappings
    │
    ├─ groupFieldsByObject()
    │    Parent-object fields (relationship path) → added to PRIMARY object's field set
    │    Child-object fields → added to child object's field set
    │
    ├─ buildFieldList(primaryObject, primaryFields)
    │    Validates each field via FLS describe
    │    Traversal paths validated via validateTraversalPath()
    │
    ├─ Dynamic SOQL: SELECT {fields} FROM {primaryObject} WHERE Id = :recordId
    │    WITH SECURITY_ENFORCED
    │
    ├─ flattenRecord() → Map<String, Object> (dot-notation keys for traversal fields)
    │
    └─ For each repeating section:
         getParentLookupField(childObject, primaryObject)
         Dynamic SOQL: SELECT {childFields} FROM {childObject} WHERE {lookupField} = :recordId
         WITH SECURITY_ENFORCED LIMIT {maxRows}
         flattenRecords() → List<Map<String, Object>>
```

### Step 4: Merge (`DocGen_MergeEngineService.mergeTemplate`)

```
Template HTML + primaryData + childData + resolvedVariables + mappings
    │
    ├─ 1. Replace system/custom variables
    │    result.replace('{{varName}}', value) — both {{varName}} and {{sys.varName}} forms
    │
    ├─ 2. processRepeatingSections()
    │    Regex: \{\{#([a-zA-Z0-9_]+)\}\}([\s\S]*?)\{\{/\1\}\}
    │    Per section: find matching childData rows, expand row template for each row
    │    Apply formatOverride per token within the row
    │
    ├─ 3. processConditionals()
    │    Regex: \{\{#if ([a-zA-Z0-9_.]+)\}\}([\s\S]*?)\{\{/if\}\}
    │    isTruthy() check on primary data value
    │    Replace with block content or empty string
    │
    └─ 4. Primary/parent field token replacement
         For each non-repeating mapping: extractValueFromData → applyFormat → replace
```

---

## 8. End-to-End Data Flow

### Template Configuration Save

```
Browser: docGenPreviewDownload.handleSaveConfig()
  → saveTemplateConfig({ configJson })
  → DocGen_Controller.saveTemplateConfig(configJson)
  → JSON.deserialize → TemplateConfigWrapper
  → DocGen_TemplateService.saveTemplateConfig(config)
    → INSERT Document_Template__c
    → Bulk INSERT Document_Field_Mapping__c (one per mapping)
    → Bulk INSERT Document_Variable__c (one per variable)
    → Re-query template for Name
    → Return TemplateSaveResultWrapper { templateId, templateName }
  → ShowToastEvent('success')
```

### Preview Generation

```
Browser: docGenPreviewDownload.handleGeneratePreview()
  → generatePreview({ configJson })
  → DocGen_Controller.generatePreview(configJson)
  → JSON.deserialize → TemplateConfigWrapper
  → DocGen_DocumentGeneratorService.generateHtml(config)
    → getTemplateText(templateId) → raw HTML
    → VariableResolverService.resolve(variables) → Map<varName, value>
    → DataResolverService.resolveData(recordId, primaryObject, mappings)
        → SOQL primary + child records → ResolvedDataWrapper
    → MergeEngineService.mergeTemplate(...) → merged HTML string
  → Return merged HTML to LWC
  → storePreviewHtml({ htmlContent: mergedHtml })
  → INSERT ContentVersion (IsMajorVersion = false)
  → Return ContentVersion ID
  → iframe src = /apex/DocGen_HtmlViewer?cvId={cvId}
  → VF page: DocGen_HtmlViewerController reads ContentVersion
    → extractBodyContent() → styles + body inner HTML
    → apex:outputText renders HTML in browser
```

### Document Download (Word)

```
Browser: docGenPreviewDownload._downloadDocument('WORD', 'application/msword')
  → generateDocument({ configJson, format: 'WORD', linkedRecordId })
  → DocGen_Controller.generateDocument(...)
  → generateHtml(config) → merged HTML
  → Blob.valueOf(mergedHtml) (HTML wrapped as Word-compatible .doc)
  → DocGen_FileService.saveDocument(content, fileName, linkedRecordId, tmplRecordId)
    → INSERT ContentVersion (IsMajorVersion = true)
    → Re-query for ContentDocumentId
    → INSERT ContentDocumentLink (linked to record, ShareType = 'V')
    → INSERT Document_Generation_Log__c (Status = 'Success')
    → Return DocumentResponseWrapper { contentDocumentId, base64Content, fileName, success }
  → _triggerBrowserDownload(base64, fileName, 'application/msword')
    → atob(base64) → Uint8Array → Blob → URL.createObjectURL → <a download>.click()
```

---

## 9. Record Page Integration & Navigation Flow

This section documents the two record-page integration components added in v1.1: `docGenEditButton` (template editing from the `Document_Template__c` page) and `docGenRecordAction` (document generation from any object record page).

---

### 9.1 Component Architecture

```
Document_Template__c record page
        │
        ├── docGenEditButton  (LWC — lightning__RecordPage, Document_Template__c only)
        │        │  1. Calls getTemplateConfig (Apex, cacheable)
        │        │  2. Serialises config → sessionStorage[EDIT_KEY]
        │        │  3. NavigationMixin → /lightning/app/DocGen_Document_Generator
        │        ▼
        └── DocGen_Document_Generator app (Standard nav, navType: Standard)
                 │
                 └── DocGen_Template_Builder_Home (HomePage flexipage)
                          └── docGenWizard.connectedCallback()
                                   │  reads + removes EDIT_KEY from sessionStorage
                                   └── enters edit mode (currentStep = 1)

Any object record page (e.g., Opportunity, Contact)
        │
        └── docGenRecordAction  (LWC — lightning__RecordPage, any object)
                 │  1. Calls getTemplatesForObject (Apex, cacheable, filtered by objectApiName)
                 │  2. On template select → getTemplateConfig → generatePreview → storePreviewHtml
                 │  3. Renders inline SLDS modal with iframe preview
                 └── Download/Save via generateDocument (Apex, non-cacheable)
```

---

### 9.2 Edit Template Navigation — Root Cause & Fix

**Root cause of navigation error:**
The `DocGen_Document_Generator` app was originally declared as `<navType>Console</navType>`. Salesforce Lightning Experience prevents navigation to Console apps from standard record pages using `standard__webPage` URL navigation — it throws _"The app you're trying to view is invalid or inaccessible."_

**Fix applied (v1.1):**
Changed `DocGen_Document_Generator.app-meta.xml` from `<navType>Console</navType>` to `<navType>Standard</navType>`. The wizard has no workspace-tab or console-specific features, so this change has no functional impact on existing behaviour.

**Why `standard__webPage` over `standard__navItemPage`:**

| Strategy | Mechanism | Cross-App? | Notes |
|---|---|---|---|
| `standard__webPage` → app URL | Full page navigation to `/lightning/app/{name}` | Yes — switches the user to the target app | Requires target app to be Standard nav |
| `standard__navItemPage` → custom tab | SPA navigation within current app's tabs | No — fails if the tab is not in the current app | Cleaner UX but only works inside DocGen app |
| Console API workspace tab | `lightning/serviceConsoleAPI` | No — only works inside a Console app | Not applicable after navType change |

`standard__webPage` was chosen because the Edit Template button may be invoked from any app (NPSP, Fundraising, Sales) that shows `Document_Template__c` records. Switching to the DocGen app is the correct user journey.

---

### 9.3 sessionStorage State Bridge

Edit state is passed from `docGenEditButton` to `docGenWizard` via `sessionStorage` rather than URL params or component properties. This design decision avoids:

- **URL length limits** — template configs with many mappings can be several KB
- **URL exposure** — mapping configurations may contain sensitive field names
- **Public `@api` prop on wizard** — adding an `@api` prop to the wizard would require it to be embedded inside a parent component and remove its ability to standalone on a flexipage

**Protocol:**

```
docGenEditButton.handleEdit()
  └── config = await getTemplateConfig(recordId)
  └── sessionStorage.setItem('docgen_edit_state', JSON.stringify(editState))
  └── NavigationMixin.Navigate → /lightning/app/DocGen_Document_Generator

docGenWizard.connectedCallback()
  └── raw = sessionStorage.getItem('docgen_edit_state')
  └── if (raw):
        sessionStorage.removeItem('docgen_edit_state')   ← always cleaned up
        this.wizardState = { ...EMPTY_STATE, ...JSON.parse(raw) }
        this._isEditMode = true
        this.currentStep = 1
```

sessionStorage is same-origin and persists across same-tab navigations, which is exactly what `NavigationMixin` performs. The key is deleted immediately after reading — subsequent page refreshes on the DocGen app open the wizard in normal (new) mode.

---

### 9.4 Edit Mode Wizard State Machine

```
Normal mode:
  Step 0 (Upload) → Step 1 (Object) → Step 2 (Mapping) → Step 3 (Variables) → Step 4 (Preview/Save)
  STEP_LABELS = ['Upload', 'Object', 'Mapping', 'Variables', 'Preview']

Edit mode (entered from sessionStorage EDIT_KEY):
  Step 1 (Object) → Step 2 (Mapping) → Step 3 (Variables) → Step 4 (Preview/Update)
  EDIT_STEP_LABELS = ['Object', 'Mapping', 'Variables', 'Preview']
  progressStep = currentStep - 1   (so step 1 renders as index 0 in the progress bar)
  Back at step 1 is blocked (cannot go before Object)

docGenPreviewDownload — edit mode detection:
  isEditMode = !!(config.existingTemplateRecordId)
  saveButtonLabel = isEditMode ? 'Update Template' : 'Save Template Config'
  handleSaveConfig:
    isEditMode  → updateTemplateConfig(existingTemplateRecordId, configJson)
    normal mode → saveTemplateConfig(configJson)
```

---

### 9.5 New Apex Methods (v1.1)

| Method | Class | Cacheable | Purpose |
|---|---|---|---|
| `getTemplateConfig(templateRecordId)` | `DocGen_Controller` | Yes | Loads full template config incl. inferred parent/child objects, token list, sys tokens |
| `getTemplatesForObject(objectName)` | `DocGen_Controller` | Yes | Returns active `Document_Template__c` records filtered by `Primary_Object__c` |
| `getSystemVariableValues()` | `DocGen_Controller` | Yes | Returns resolved `sys.*` key-value pairs for UI display |
| `updateTemplateConfig(templateRecordId, configJson)` | `DocGen_Controller` | No | Delete-and-re-insert all child mappings/variables for an existing template |
| `extractSysTokens(contentVersionId)` | `DocGen_Controller` | No | Parses `{{sys.*}}` tokens from a ContentVersion's HTML body |

**`loadTemplateConfig` parent/child inference logic** (`DocGen_TemplateService`):

The service infers parent/child objects from saved `Document_Field_Mapping__c` records rather than storing them explicitly:
- Child: any mapping where `Is_Repeating_Section__c = true` → read `Repeat_Object__c`
- Parent: any non-repeating mapping where `Source_Object__c ≠ primaryObject` AND `Relationship_Path__c` is non-blank

Object labels are resolved via `Schema.getGlobalDescribe().get(apiName).getDescribe().getLabel()`.

**`updateTemplateConfig` pattern:**

```apex
// 1. Update the Document_Template__c record
// 2. Delete all existing Document_Field_Mapping__c children
delete [SELECT Id FROM Document_Field_Mapping__c WHERE Document_Template__c = :id];
// 3. Delete all existing Document_Variable__c children
delete [SELECT Id FROM Document_Variable__c WHERE Document_Template__c = :id];
// 4. Re-insert fresh mapping and variable records from configJson
```

This delete-and-re-insert approach avoids the complexity of diffing existing records. It requires `allowDelete = true` on both child objects in the `DocGen_Full_Access` permission set (already granted).

---

### 9.6 New LWC Components (v1.1)

#### `docGenEditButton`

| Property | Value |
|---|---|
| Target | `lightning__RecordPage` |
| Object restriction | `Document_Template__c` only (via `<targetConfig><objects>`) |
| `@api` props | `recordId` |
| Apex calls | `getTemplateConfig` (cacheable) |
| Navigation | `NavigationMixin` → `standard__webPage` → `/lightning/app/DocGen_Document_Generator` |
| State handoff | `sessionStorage['docgen_edit_state']` |

#### `docGenRecordAction`

| Property | Value |
|---|---|
| Target | `lightning__RecordPage`, `lightning__AppPage` |
| Object restriction | None (works on any object) |
| `@api` props | `recordId`, `objectApiName` (both injected by the record page) |
| Apex calls | `getTemplatesForObject`, `getTemplateConfig`, `generatePreview`, `storePreviewHtml`, `generateDocument` |
| UI pattern | SLDS modal (`slds-modal slds-fade-in-open` + `slds-backdrop slds-backdrop_open`) |
| Views | `select` (template list) → `preview` (iframe + download buttons) |
| Preview | `<iframe src="/apex/DocGen_HtmlViewer?cvId={previewCvId}">` — LWS-safe, no Blob |

---

## 10. Security Model

### Sharing

| Class | Sharing | Reason |
|---|---|---|
| `DocGen_Controller` | `with sharing` | Entry point must respect user's record visibility |
| `DocGen_SchemaService` | `with sharing` | Schema describe filtered by `isAccessible()` — FLS enforced |
| `DocGen_TemplateService` | `with sharing` | Template insert/query respects record access |
| `DocGen_DataResolverService` | `with sharing` | All SOQL uses `WITH SECURITY_ENFORCED` |
| `DocGen_DocumentGeneratorService` | `with sharing` | Inherits record visibility for document generation |
| `DocGen_FileService` | `with sharing` | File insert/link respects record access |
| `DocGen_VariableResolverService` | `with sharing` | UserInfo reads only — no SOQL risk |
| `DocGen_MergeEngineService` | `public` (no sharing) | No SOQL — pure string processing, no record access |
| `DocGen_HtmlViewerController` | `without sharing` | Preview ContentVersions are system-generated and not owned by the running user |

### Field-Level Security

All schema describe calls filter by `dfr.isAccessible()`. All dynamic SOQL includes `WITH SECURITY_ENFORCED`. The `buildFieldList` method validates each requested field independently before including it in the query.

### SOQL Injection Prevention

- Object and field names pass through `validateObjectName` which pattern-matches against `[a-zA-Z0-9_]+`
- Traversal paths are validated field-by-field via `validateTraversalPath` using schema descriptors
- Record IDs are passed as bind variables (`:recordId`), never string-concatenated

### CRUD Checks

Before any DML:
- `Schema.sObjectType.ContentVersion.isCreateable()` — checked in `DocGen_TemplateService.uploadTemplateContent` and `DocGen_FileService.saveDocument`
- `Schema.sObjectType.Document_Template__c.isCreateable()` — checked in `DocGen_TemplateService.saveTemplateConfig`

### Permission Set

`DocGen_Full_Access` grants:
- CRUD on `Document_Template__c`, `Document_Field_Mapping__c`, `Document_Variable__c`, `Document_Generation_Log__c`
- Read/Create on `ContentVersion`, `ContentDocumentLink`
- Read on `DocGen_Config__mdt`
- Access to the `docGenWizard` LWC and the `DocGen_HtmlViewer` VF page

---

## 11. Deployment Guide

### Prerequisites

- Salesforce CLI (`sf`) installed and authenticated
- Node.js for local linting (optional)
- Target org with API version 66.0 or higher

### Deploy All Metadata

```bash
# Deploy full source tree
sf project deploy start --source-dir force-app/ --target-org <alias>

# Assign permission set
sf org assign permset --name DocGen_Full_Access --target-org <alias>

# Verify
sf org open --target-org <alias>
```

### Deploy Incrementally (Specific Components)

```bash
# Apex classes only
sf project deploy start --source-dir force-app/main/default/classes/

# Specific component
sf project deploy start --metadata LightningComponentBundle:docGenWizard

# VF page
sf project deploy start --metadata ApexPage:DocGen_HtmlViewer
```

### Post-Deployment Steps

1. Create `DocGen_Config__mdt.Default` record (see [Custom Metadata](#3-custom-metadata))
2. Navigate to **Document Generator** app and verify the wizard loads
3. Upload the sample template from `docs/sample_donation_acknowledgment.html`
4. Walk through the wizard with a real Opportunity record ID to confirm end-to-end flow

---

## 12. Extensibility

### Adding a New Variable Type

1. Add the new type to `Document_Variable__c.Variable_Type__c` picklist field metadata
2. Add a `when 'NEW_TYPE'` branch in `DocGen_VariableResolverService.resolve()`
3. The LWC `docGenVariablesPanel` currently passes `variables: []` — extend the panel's UI to capture the new variable's configuration fields

### Adding a New Format Override

Add a new `if (fType == 'myformat')` branch in `DocGen_MergeEngineService.applyFormat()`. The format string entered in the wizard is passed through as-is.

### Adding a New Output Format

1. Add a new picklist value to the format selector in `docGenPreviewDownload.html`
2. Add a handler in `docGenPreviewDownload.js` that calls `_downloadDocument('MYFORMAT', 'mime/type')`
3. Add format handling in `DocGen_Controller.generateDocument` (switch on the `format` parameter)
4. Implement conversion in `DocGen_DocumentGeneratorService`

### Supporting Multiple Templates per Record Type

The current architecture supports one template configuration per generation session. To support a template library:
1. Query `Document_Template__c` records (filtered by `Primary_Object__c` = current object) in a template picker LWC
2. Load the template's `Document_Field_Mapping__c` records and pass them as `savedMappings` to `docGenMappingBuilder`
3. Skip Steps 0–2 of the wizard when loading a saved template

---

## 13. Known Constraints & Design Decisions

### Why no `EntityDefinition` SOQL?
`EntityDefinition` LIKE queries triggered internal server errors in this org (likely due to `queryMore` limitations on this object type). The replacement uses `Schema.getGlobalDescribe()` key-based filtering — pure in-memory, no SOQL, no governor limit concerns.

### Why Visualforce for preview/PDF and not a blob URL?
Lightning Web Security (LWS) blocks:
- `iframe.srcdoc` attribute assignment
- `new Blob([htmlString], { type: 'text/html' })` — `text/html` is not on the LWS allowlist
- `window.open()` with a blob URL

The VF page approach is the only fully supported path for rendering HTML content in an iframe within LWC.

### Why `extractBodyContent` in the VF controller?
Without it, injecting a full HTML document (with `<html><head>...</head><body>`) inside VF's own HTML wrapper creates a nested document. The HTML5 spec (tree construction rules) silently drops the inner `<head>` tag when encountered in "in body" insertion mode. This causes the template's `<style>` blocks to lose scope, collapsing the layout. Extracting just the styles and body content prevents this entirely.

### Why `templateTokens` is canonical in the mapping builder?
If `savedMappings` were used as the primary list, re-uploading a template with changed tokens would show stale rows. The token list from the current template file is always authoritative — saved mappings only supply pre-filled values for tokens that still exist. This also means tokens added to the template after the last save appear as fresh (unmapped) rows, and removed tokens disappear from the mapping screen without leaving orphan rows.

### Why is `docGenMappingBuilder` a child component, not route-based?
The wizard uses conditional rendering (`if:true={isStep2}`) rather than routing. This keeps all step state in the parent's `wizardState` object and avoids navigation complexity. Session storage provides persistence across page refreshes.

### `DocGen_MergeEngineService` — no sharing
The merge engine operates only on pre-resolved data passed in as method parameters. It executes no SOQL and accesses no records directly. Sharing mode is irrelevant. The `public` (implicit without sharing in static context) declaration is intentional — it avoids any ambiguity and signals that sharing is not a concern here.
