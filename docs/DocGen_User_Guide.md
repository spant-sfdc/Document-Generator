# DocGen — User Guide

**Document Generation System for Salesforce**  
**Version:** 1.1 | **Updated:** April 2026  
**Org:** nonprofit-demo-org-1 (`spant-9csk@force.com`)

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Prerequisites](#2-prerequisites)
3. [Setup Guide](#3-setup-guide)
4. [Using the Wizard — Step by Step](#4-using-the-wizard--step-by-step)
   - [Step 1: Upload Template](#step-1-upload-template)
   - [Step 2: Select Objects](#step-2-select-objects)
   - [Step 3: Map Tokens](#step-3-map-tokens)
   - [Step 4: System Variables](#step-4-system-variables)
   - [Step 5: Preview & Download](#step-5-preview--download)
5. [Editing an Existing Template](#5-editing-an-existing-template)
6. [Generating Documents from a Record Page](#6-generating-documents-from-a-record-page)
7. [Template Authoring Guide](#7-template-authoring-guide)
   - [Simple Field Tokens](#simple-field-tokens)
   - [Parent Object Tokens](#parent-object-tokens)
   - [Repeating Section Tokens](#repeating-section-tokens)
   - [Conditional Block Tokens](#conditional-block-tokens)
   - [System Variable Tokens](#system-variable-tokens)
   - [Format Overrides](#format-overrides)
8. [Common Errors & Troubleshooting](#8-common-errors--troubleshooting)
9. [Best Practices](#9-best-practices)

---

## 1. Introduction

DocGen is a native Salesforce document generation system that merges live record data into HTML templates. It requires no managed packages or external services — everything runs inside your org using LWC, Apex, and standard Salesforce platform features.

**What you can do with DocGen:**
- Author HTML templates with merge tokens (`{{TokenName}}`)
- Map each token to any Salesforce object field, a constant text value, or a system variable
- Pull data from a primary object, its parent records (via lookups), and child records (repeating rows)
- Preview merged documents in-browser before downloading
- Download the output as a formatted PDF (opened in a new browser tab for printing/saving)
- Save the generated file directly to Salesforce Files, linked to any record
- Save the template configuration for reuse

---

## 2. Prerequisites

Before using DocGen, confirm the following are in place:

| Requirement | Details |
|---|---|
| Permission set assigned | `DocGen_Full_Access` must be assigned to your user |
| Access to DocGen app | Navigate to the **Document Generator** app from the App Launcher |
| Template file | An HTML file authored with `{{TokenName}}` merge syntax |
| Object field access | FLS (Field-Level Security) access to all fields you intend to map |
| Record ID (for final output) | The 15- or 18-digit Salesforce record ID of the record to merge data from |

To verify your permission set: Setup → Users → your user → Permission Set Assignments → confirm `DocGen_Full_Access` appears.

---

## 3. Setup Guide

### Clone & Deploy (First-Time Setup)

```bash
# 1. Clone the repository
git clone <repository-url>
cd nonprofit-demo-org1

# 2. Authorize your org
sf org login web --alias nonprofit-demo-org1 --set-default

# 3. Deploy all metadata
sf project deploy start --source-dir force-app/

# 4. Assign the permission set to yourself
sf org assign permset --name DocGen_Full_Access

# 5. Verify deployment
sf org open
```

### Configure DocGen Custom Metadata (Required for System Variables)

1. In Salesforce Setup, search for **Custom Metadata Types**
2. Open **DocGen Config**
3. Click **Manage DocGen Configs → New**
4. Create a record with **Label** = `Default` (DeveloperName must be `Default`)
5. Fill in these fields:

| Field | Description | Example |
|---|---|---|
| Org Display Name | Name shown in `{{sys.orgName}}` | `Hope Foundation` |
| Org EIN | Federal tax ID for `{{sys.orgEIN}}` | `12-3456789` |
| Org Address | Address for `{{sys.orgAddress}}` | `100 Main St, Chicago, IL 60601` |
| Org Phone | Phone for `{{sys.orgPhone}}` | `(312) 555-0100` |
| Org Website | URL for `{{sys.orgWebsite}}` | `https://hopefoundation.org` |
| Max Repeating Rows | Cap on child records per section | `200` |

Without this record, `sys.orgEIN`, `sys.orgAddress`, `sys.orgPhone`, and `sys.orgWebsite` will render as blank.

---

## 4. Using the Wizard — Step by Step

Open the **Document Generator** app from the App Launcher. The wizard is on the app home page. The wizard has 5 steps shown in the progress bar at the top.

---

### Step 1: Upload Template

**What happens here:** You select and upload your HTML template file. DocGen extracts all merge tokens automatically.

1. Click **Choose File** and select your `.html` template
2. Wait for the upload indicator to complete (file is stored as a Salesforce ContentVersion)
3. The **Detected Tokens** panel shows every `{{TokenName}}` found in your file
4. Review the list — these are the exact tokens you will map in Step 3
5. Click **Next** to proceed

**What tokens are detected:**
- Section markers like `{{#OpportunityLineItem}}` appear first (sorted alphabetically)
- Field tokens like `{{DonorName}}` appear after
- `{{sys.*}}` tokens are excluded — they resolve automatically
- `{{#if FieldName}}` blocks are excluded — they are conditional directives, not mappable fields

> **Important:** If you upload a new file after coming back to Step 1, all previous mappings are cleared. This prevents stale token data from a prior template.

---

### Step 2: Select Objects

**What happens here:** You tell DocGen which Salesforce objects your template draws data from.

#### Select the Primary Object

The primary object is the main record the document is generated for (e.g., `Opportunity`, `Contact`, `Account`).

1. Type at least 2 characters of the object name in the search box
2. Click the **Search** button (or press Enter)
3. Click the object name from the results list
4. The selected object appears as a chip labeled **Primary**

> You can remove the primary selection with the **×** on the chip, which also clears all parent and child selections.

#### Add Parent Objects (Optional)

Parent objects are records related to the primary record via a lookup field (e.g., `Account` related to `Opportunity` via the `AccountId` lookup).

1. Click the **Parent** tab (displayed after a primary object is selected)
2. Search and select the parent object
3. Parent chips appear below labeled **(Parent)**

#### Add Child Objects (Optional)

Child objects have multiple records related to the primary record (e.g., `OpportunityLineItem` related to `Opportunity`). Each child object produces a repeating section in the output.

1. Click the **Child** tab
2. Search and select the child object
3. If the section marker `{{#ApiName}}` for this child is not present in your template, a warning appears:
   > *"No repeating section found for: Opportunity Line Item. Add `{{#ApiName}}...{{/ApiName}}` blocks to your template or remove these objects."*
4. You can still proceed — the section will simply produce no rows

Click **Next** when your object selections are complete.

---

### Step 3: Map Tokens

**What happens here:** You specify what Salesforce field (or constant value) each template token represents.

Each detected token gets its own mapping row with these controls:

| Control | Description |
|---|---|
| **Token** | The `{{TokenName}}` placeholder from your template (read-only) |
| **Mapping Type** | Field, Constant, or Variable |
| **Source Object** | Which object to pull data from |
| **Source Field** | The specific field on that object |
| **Format Override** | Optional format string (see Format Overrides section) |
| **Static Value** | Text to use when Mapping Type = Constant |

#### Mapping Type: Field

- Select the source object from the dropdown (Primary, Parent, or Child objects)
- Select the field from the **Source Field** dropdown
- For parent object fields, a **Relationship Path** (e.g., `Account.Name`) is set automatically

#### Mapping Type: Constant

- Enter a fixed text value in the **Static Value** field
- The same text will appear in every generated document, regardless of record data

#### Repeating Section Tokens (`{{#ObjectName}}`)

- These rows represent the header/anchor of a repeating child section
- The **Source Object** is pre-set to the matching child object
- Map additional tokens inside the section (ItemName, ItemDate, etc.) to fields on the child object

#### After Mapping

Click **Next** to proceed. Your mappings are preserved in session storage — if you navigate back and return to Step 3, your selections are restored.

---

### Step 4: System Variables

**What happens here:** Review the system variables that auto-populate in every document. No configuration is needed on this screen.

| Token | Value |
|---|---|
| `{{sys.today}}` | Today's date |
| `{{sys.currentUser}}` | Running user's full name |
| `{{sys.orgName}}` | Org display name (from DocGen Config or Org Name) |
| `{{sys.userEmail}}` | Running user's email address |
| `{{sys.orgEIN}}` | Federal EIN (from DocGen Config custom metadata) |
| `{{sys.orgAddress}}` | Org address (from DocGen Config custom metadata) |
| `{{sys.orgPhone}}` | Org phone (from DocGen Config custom metadata) |
| `{{sys.orgWebsite}}` | Org website (from DocGen Config custom metadata) |

Click **Next** to proceed to Preview.

---

### Step 5: Preview & Download

**What happens here:** Enter a record ID, generate a merged preview, and download or save the final document.

#### Generate Preview

1. Enter the **Record ID** of the Salesforce record to merge data from (e.g., an Opportunity ID)
2. Click **Generate Preview**
3. Wait for the document to render in the preview pane
4. Review the merged output — check that field values, repeating rows, and conditional blocks appear correctly

#### Open as PDF

1. After generating the preview, click **Open as PDF (New Tab)**
2. The merged document opens in a new browser tab
3. Use your browser's **Print** dialog (Ctrl+P / Cmd+P) and select **Save as PDF** to download

#### Download as Word

1. Click **Download as Word (.doc)**
2. The file is saved to your local machine and also stored in Salesforce Files
3. If a Record ID was provided, the file is attached to that record

#### Save Template Configuration

1. Click **Save Template Config** to persist the template + mapping definitions to Salesforce
2. A `Document_Template__c` record is created with all field mappings stored as `Document_Field_Mapping__c` child records
3. A success toast displays the template name and record ID
4. Click **View Template Record** to navigate directly to the saved template

---

## 5. Editing an Existing Template

Once a template has been saved, you can reopen its configuration in the wizard at any time to update object selections, token mappings, or variables — without re-uploading the HTML file.

### How to Edit

1. Navigate to the **Document Templates** tab (inside the **Document Generator** app, or via App Launcher → Document Templates)
2. Open the `Document_Template__c` record for the template you want to edit
3. Find the **Edit Template** button on the record page (placed there by your administrator)
4. Click **Edit Template**
   - DocGen loads the saved configuration in the background
   - You are redirected to the **Document Generator** app
   - The wizard opens directly at **Step 2: Select Objects** — there is no re-upload step
5. Make your changes across Steps 2–5 (Object, Mapping, Variables, Preview)
6. On Step 5, click **Update Template** (the save button relabels automatically in edit mode)
7. A success message confirms the template was updated

### What Changes in Edit Mode

| Feature | Normal (New) | Edit Mode |
|---|---|---|
| First step shown | Upload Template (Step 1) | Select Objects (Step 2) |
| Progress bar labels | Upload, Object, Mapping, Variables, Preview | Object, Mapping, Variables, Preview |
| Header badge | *(none)* | **Editing Template** badge |
| Cancel button | Reset Wizard | Cancel Edit (resets to new-template mode) |
| Save button label | Save Template Config | Update Template |
| Save behavior | Creates a new `Document_Template__c` | Updates the existing record + all child mappings |

### What Is Preserved

- The original HTML template file is unchanged (no re-upload required)
- All previously saved token mappings are pre-loaded in Step 3
- Previously configured variables are restored in Step 4
- You can add or remove object selections in Step 2 — changed objects cause downstream mapping rows to be refreshed accordingly

> **Note:** Clicking **Update Template** replaces all child `Document_Field_Mapping__c` and `Document_Variable__c` records. Any manual edits made directly to those child records (outside the wizard) will be overwritten.

---

## 6. Generating Documents from a Record Page

The **Generate Document** button can be placed on any Salesforce object's record page by your administrator. It allows end users to generate documents for the record they are currently viewing — without leaving the page or opening the DocGen app.

### How to Use

1. Open any record that has the **Generate Document** button in its page layout (e.g., an Opportunity or Contact record)
2. Click **Generate Document**
3. A modal dialog opens showing all active templates configured for this object type
4. Click any template name to select it
   - DocGen loads the template configuration and merges the current record's data automatically
   - A live preview renders in the modal window
5. From the preview, choose one of three actions:

| Action | Description |
|---|---|
| **Open as PDF (New Tab)** | Opens the merged document in a new browser tab; use browser Print → Save as PDF |
| **Download as Word** | Downloads a `.doc` file to your local machine and saves a copy to Salesforce Files |
| **Save to Salesforce Files** | Saves a PDF to Salesforce Files linked to this record; a "View File" link appears after saving |

6. Click **Back to Templates** to choose a different template, or **Close** to dismiss the modal

### What the User Sees

```
┌──────────────────────────────────────┐
│ Generate Document                    │
│                                      │
│ Choose a template:                   │
│  📄 Donation Acknowledgement (Opp)  │
│  📄 Grant Award Letter (Opp)        │
│  📄 Pledge Confirmation (Opp)       │
│                                      │
│ [Close]                              │
└──────────────────────────────────────┘
         ↓ (after selecting a template)
┌──────────────────────────────────────┐
│ Preview — Donation Acknowledgement   │
│ ┌──────────────────────────────────┐ │
│ │  [Merged HTML Preview]           │ │
│ └──────────────────────────────────┘ │
│ [Open as PDF] [Download as Word]     │
│ [Save to Salesforce Files]           │
│ [Back to Templates] [Close]          │
└──────────────────────────────────────┘
```

### Notes for End Users

- Only templates marked **Active** and configured for the current object type appear in the list
- The current record's ID is used automatically — there is no Record ID input required
- If no templates exist for this object, the modal shows an empty state with a link to the Document Generator app
- The modal does not navigate away from the record — you remain on the record page throughout

---

## 7. Template Authoring Guide

DocGen templates are plain HTML files. Use the `{{TokenName}}` syntax to mark where Salesforce field values should appear.

### Simple Field Tokens

Replaced with a single field value from the primary object.

```html
<p>Dear {{DonorName}},</p>
<p>Your donation of {{TotalAmount}} was received on {{CloseDate}}.</p>
```

Map in Step 3:
- `{{DonorName}}` → Source Object: Opportunity, Source Field: `Name`
- `{{TotalAmount}}` → Source Object: Opportunity, Source Field: `Amount`, Format: `currency`
- `{{CloseDate}}` → Source Object: Opportunity, Source Field: `CloseDate`, Format: `date:MM/dd/yyyy`

---

### Parent Object Tokens

Tokens mapped to fields on a parent object (related via a lookup on the primary object).

```html
<div>{{DonorOrgName}}</div>
<div>{{DonorCity}}, {{DonorState}}</div>
```

Map in Step 3:
- `{{DonorOrgName}}` → Source Object: Account (Parent), Source Field: `Name`
  → Relationship Path auto-set to `Account.Name`
- `{{DonorCity}}` → Source Object: Account (Parent), Source Field: `BillingCity`
  → Relationship Path: `Account.BillingCity`

> **Key rule:** The relationship path is set automatically when you choose a parent object and field. DocGen queries these as traversal fields on the primary object's SOQL query (e.g., `SELECT Account.Name, Account.BillingCity FROM Opportunity WHERE Id = :recordId`).

---

### Repeating Section Tokens

Sections that repeat once per child record. Use `{{#ApiName}}` to open and `{{/ApiName}}` to close.

```html
<table>
  <thead>
    <tr><th>Item</th><th>Qty</th><th>Price</th></tr>
  </thead>
  <tbody>
    {{#OpportunityLineItem}}
    <tr>
      <td>{{ItemName}}</td>
      <td>{{ItemQty}}</td>
      <td>{{ItemUnitPrice}}</td>
    </tr>
    {{/OpportunityLineItem}}
  </tbody>
</table>
```

**Critical rules:**
1. `ApiName` in the section markers **must exactly match** the Salesforce object API name (e.g., `OpportunityLineItem`, not `LineItems` or `DonationItems`)
2. All tokens inside the section must be mapped to fields on the child object
3. The child object must be added in Step 2 — Object Selection

---

### Conditional Block Tokens

Show or hide a block based on whether a field is truthy.

```html
{{#if IsMajorDonor}}
<div class="major-donor-box">
  Thank you for being a Major Donor this fiscal year!
</div>
{{/if}}
```

Map `{{IsMajorDonor}}` to a checkbox or boolean field on the primary object. The block renders only when the field value is `true`, `1`, or any non-empty, non-false, non-zero string.

> **Note:** `{{#if FieldName}}` is NOT shown in the token list and does NOT need a mapping row. It is resolved at merge time using the mapping for `{{IsMajorDonor}}` (the inner field token).

---

### System Variable Tokens

Auto-resolved — no mapping needed.

```html
<div>Date: {{sys.today}}</div>
<div>Prepared by: {{sys.currentUser}}</div>
<div>{{sys.orgName}} · EIN: {{sys.orgEIN}}</div>
```

These tokens are replaced before any field mapping runs. They are sourced from `UserInfo` API and the `DocGen_Config__mdt.Default` custom metadata record.

---

### Format Overrides

Apply a format to transform raw field values. Enter the format string in the **Format Override** column in Step 3.

| Format String | Example Input | Example Output |
|---|---|---|
| `date:MM/dd/yyyy` | `2024-12-31` | `12/31/2024` |
| `date:MMMM d, yyyy` | `2024-12-31` | `December 31, 2024` |
| `currency` | `12500` | `$12,500.00` |
| `number:0` | `3.0` | `3` |
| `number:2` | `1234.5` | `1234.50` |
| `upper` | `hello world` | `HELLO WORLD` |
| `lower` | `HELLO WORLD` | `hello world` |

---

## 8. Common Errors & Troubleshooting

### "No repeating section found for: [Object Name]"

**Cause:** You added a child object in Step 2, but the template does not contain a matching `{{#ApiName}}` section marker.

**Fix:** Either:
- Add `{{#ApiName}}...{{/ApiName}}` blocks to your template (use the exact Salesforce API name)
- Or remove the child object from Step 2

---

### Preview shows "No preview content found"

**Cause:** The preview ContentVersion ID was not stored correctly, or session was refreshed.

**Fix:** Click **Generate Preview** again with a valid Record ID.

---

### Preview is blank or shows only partial content

**Cause:** The Record ID is invalid or the running user does not have FLS access to the mapped fields.

**Fix:**
1. Verify the Record ID points to an existing record of the correct object type
2. Check that the user has Read access to all mapped fields
3. Confirm the primary object API name matches the record type

---

### Token appears unreplaced in output (e.g., `{{DonorName}}` in final document)

**Cause:** The token has no mapping row, the mapping type is FIELD but no source field was selected, or the field name has a typo in the token vs. the mapping.

**Fix:** Return to Step 3 and verify each token has a complete mapping (object + field selected). Token names are case-sensitive — `{{DonorName}}` and `{{donorname}}` are different tokens.

---

### "Lightning Web Security: Unsupported MIME type" error

**Cause:** You are running an older version of the preview component that used Blob-based PDF generation, which is blocked by Lightning Web Security.

**Fix:** Ensure you have the latest version deployed. The current implementation opens the PDF via a Visualforce page URL — no Blob creation is needed.

---

### Field dropdown is empty in Step 3

**Cause:** The running user lacks FLS Read access to fields on the selected object.

**Fix:** Go to Setup → Object Manager → [Object] → Fields & Relationships → verify the field is visible to your profile or permission set.

---

### Repeating rows do not appear in output

**Cause:** The section API name in the template does not match the child object API name, or no child records exist for the record ID entered.

**Fix:**
1. Check the section marker: `{{#OpportunityLineItem}}` must use the exact API name
2. Query the org to confirm child records exist: run a report or check the related list on the primary record

---

## 9. Best Practices

### Template Design

- **Match section names exactly.** The section marker `{{#SectionName}}` must use the Salesforce API name character-for-character (case-insensitive match, but use exact case for clarity).
- **Keep tokens out of HTML comments.** The merge engine processes the full raw HTML, including comments. If a token appears in a comment, it will be extracted and shown in the token list.
- **Use system variables for org-level data.** Never hardcode your org name, EIN, or phone in templates — use `{{sys.orgName}}` so changes propagate automatically.
- **One primary object per template.** DocGen supports one primary object with unlimited parents and children. If you need data from two unrelated objects, consider a custom Apex approach.

### Token Naming

- Use descriptive, human-readable token names: `{{DonorFullName}}` is clearer than `{{F1}}`.
- Avoid spaces and special characters in token names. Use camelCase or PascalCase.
- Do not use `sys.` as a prefix — it is reserved for system variables.

### Field Mappings

- Always select a **Source Field** when Mapping Type is Field — leaving it blank means the token renders empty.
- Use **Format Override** for dates and currency — raw Salesforce values use ISO format (e.g., `2024-12-31`) which may not match your document's requirements.
- For parent object fields, verify the **Relationship Path** is set correctly (e.g., `Account.Name`).

### Session Management

- The wizard saves state to browser `sessionStorage`. If you close and reopen the tab, state is lost.
- After uploading a new template, return through all steps to re-map tokens — previous mappings are automatically cleared.
- To start completely fresh, use the **Reset** button on the wizard.

### Testing

- Always test with a real Record ID that has representative data, including at least one child record if your template has repeating sections.
- Test the conditional blocks by using a record where the boolean field is `true` and another where it is `false` — confirm the block appears/disappears correctly.
- Review the PDF output in multiple browsers. Chrome and Edge render the HTML-to-PDF print dialog most consistently.
