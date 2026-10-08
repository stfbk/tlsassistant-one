# TLSAssistant OpenNebula Marketplace Appliance

OpenNebula Community Marketplace appliance for [TLSAssistant](https://github.com/stfbk/tlsassistant), an open-source modular framework capable of identifying a wide range of TLS vulnerabilities and assessing compliance with multiple guidelines.

This appliance wraps the official `stfbk/tlsassistant` Docker container, automating the execution of TLS scans and securely delivering the resulting PDF reports to any S3-compatible object storage to be easily retrieved by the user.

## Quick Start

1. **Deploy the Appliance:** Instantiate the template from Sunstone.
2. **Provide your Target:** In the contextualization tab, enter the `TARGET_URL` (e.g., `www.yourcompany.com`) that you want the appliance to scan.
3. **Configure S3 Storage:** Provide your `S3_ENDPOINT`, `S3_BUCKET`, and credentials.
4. **Set the Variables:** In the instantitation wizard you can set various flags and parameters to model the scan to your needs.
5. **Retrieve your Report:** Once the appliance boots and completes the scan, it will push the URLs of the PDF report back to OpenNebula via OneGate *(Note: Ensure OneGate is enabled in your VM networks)*. You can view these links directly in the VM's **Template** tab in Sunstone.

## Configuration Parameters

The appliance is customizable via OpenNebula Contextualization.

> **Note:** Parameter naming conventions might change between releases. Verify the exact variable names via the OpenNebula template wizard.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `ONEAPP_SCAN_ENDPOINT_TARGET_URL` | The endpoint/hostname you want to scan. | `opennebula.io` |
| `ONEAPP_SCAN_ENDPOINT_RESOLVE_IP` | Adds `--resolve-ip` to the scan command. | `NO` |
| `ONEAPP_SCAN_VULN_MODULES` | Scan modules selected in OpenNebula and converted to `-m` arguments. Use `none` for compliance-only scans. | `all` |
| `ONEAPP_STORAGE_S3_ENDPOINT` | The S3 API endpoint used to upload the report. | *(Required)* |
| `ONEAPP_STORAGE_S3_BUCKET` | The destination bucket name. | `tlsa-reports` |
| `ONEAPP_STORAGE_S3_ACCESS_KEY` | S3 Access Key ID. | *(Required)* |
| `ONEAPP_STORAGE_S3_SECRET_KEY` | S3 Secret Access Key. | *(Required)* |
| `ONEAPP_STORAGE_S3_REGION` | S3 region used for Signature V4 calculation. | `us-east-1` |
| `ONEAPP_STORAGE_S3_CUSTOM_HOST_IP` | Optional IP address mapped to the `ONEAPP_STORAGE_S3_ENDPOINT` hostname via `/etc/hosts`. | *None* |
| `ONEAPP_COMPLIANCE_CONFIG_ENABLED` | Enables compliance scanning. | `NO` |
| `ONEAPP_COMPLIANCE_CONFIG_COMPAREMANY` | Chooses `compare_many` instead of `compare_one`. | `NO` |
| `ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_ONE` | Single guideline used with `compare_one`. | `ACN` |
| `ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_MANY` | Ordered comma-separated guideline list used with `compare_many`. Use `custom` to inject the custom list. | `ACN,NIST` |
| `ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_CUSTOM` | Custom guideline string substituted where `custom` appears in the many-guidelines list. | *(Empty)* |
| `ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_FILENAME` | Name of the [file injected](#file-injection-for-custom-guidelines) for the custom guidelines | `custom_guidelines.json` |
| `ONEAPP_COMPLIANCE_EXTRA_SECURITY` | Adds `--security=true` when enabled. | `NO` |
| `ONEAPP_COMPLIANCE_EXTRA_OPENSSL_VERSION` | Adds `--openssl [version]` or `--ignore-openssl` (which defaults to the latest LTS) | `ignore` |

## Template Seeding

Since this appliance is intended to be ephemeral, instantiating new VMs for different scans means you would normally have to re-enter some fixed values every time. To avoid this, you can seed the template with your permanent values.

**How to seed the template (via SunStone or CLI):**
1. **Clone** the base appliance template.
2. **Remove** the target variable from the `USER_INPUTS` list.
3. **Add/Edit** the variable directly inside the `CONTEXT` list with your hardcoded value.

**Example (seeding the S3 endpoint):**

**Before (default):**
```text
CONTEXT = [
	...
	ONEAPP_STORAGE_S3_ENDPOINT = "$ONEAPP_STORAGE_S3_ENDPOINT"
	...
]
USER_INPUTS = [ 
	...
	ONEAPP_STORAGE_S3_ENDPOINT = "M|text|S3 API Endpoint||"
	...
]
```
**After (seeded):**
```text
CONTEXT = [
	...
	ONEAPP_STORAGE_S3_ENDPOINT = "http://my-storage-endpoint:9000"
	...
]
```
## File Injection for Custom Guidelines

To evaluate a target against a proprietary or [modified compliance framework](https://github.com/stfbk/tlsassistant/wiki/Custom-Guidelines), you must inject the raw JSON ruleset directly into the ephemeral instance using OpenNebula's native file contextualization mechanism (`FILES_DS`).

### 1. Upload the Ruleset to the Datastore
1. In SunStone, navigate to **Storage** -> **Files**.
2. Click **+** to upload your JSON file.
3. **CRITICAL:** Ensure the **Type** is set to **`CONTEXT`**.

### 2. Attach the File to the Template Context
1. Clone and edit the VM Template configuration.
2. Navigate to the **Context** tab, then open the **Files** sub-tab.
3. Select your uploaded JSON file from the list. This tells OpenNebula to include the file payload on the generated context ISO block storage device during VM provisioning.

### 3. Match Context Environment Variables
The appliance relies on specific variable combinations to find and parse the injected file. Set the following in your contextualization settings:

* **`ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_FILENAME`**: Must match the exact filename of the uploaded file.
* **`ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_CUSTOM`**: Must match the target framework alias defined *inside* your custom JSON file structure.

## S3 Networking & URL Generation (Important)

Because pre-signed S3 URLs are cryptographically tied to the Hostname and Region they are generated for, networking must be configured correctly for the report links to work in your browser.

### The "Double-Link" Output Strategy
To maximize accessibility, the appliance pushes **two** URL formats to OneGate once the scan is complete:

1. **`REPORT_URL` (Secure Presigned Link):** A cryptographically signed URL valid for 7 days. This is best for strict, private S3 buckets. *Note: Your browser's clock and the OpenNebula Host clock must be in sync, or the S3 provider will reject the signature with an `AccessDenied` error.*
2. **`PUBLIC_URL` (Clean Fallback Link):** A standard, unsigned URL. If you configure your S3 bucket to allow anonymous/public downloads (e.g., `mc anonymous set download`), use this link to bypass signature and clock-skew issues entirely.

### Local Storage & Split-Horizon DNS
If you are deploying a local S3 provider and referencing it via a custom hostname (e.g., `http://my-storage-endpoint:9000`), the appliance must be able to resolve that hostname.

If your OpenNebula Virtual Network does not provide an internal DNS server capable of resolving your custom S3 domain, you can use the **`ONEAPP_STORAGE_S3_CUSTOM_HOST_IP`** parameter. By passing the S3 server's IP (e.g., `172.16.100.50`) here, the appliance will automatically map it to the hostname in its `/etc/hosts` file before attempting the upload.

**Rule of Thumb:** Ensure that the `ONEAPP_STORAGE_S3_ENDPOINT` string provided to the appliance matches exactly how your local browser will access the S3 server, as this string is baked into the generated URLs.

## Error Codes

When the appliance bootstrap fails, an `ERROR_MESSAGE` is pushed to OpenNebula via OneGate and the VM shuts down. The error messages correspond to the following internal codes:

| Code | Description |
|------|-------------|
| `1` | The custom guideline file could not be found. The missing filename is reported in the error message. |
| `2` | The S3 endpoint could not be resolved. Double-check DNS, routing, and the `ONEAPP_STORAGE_S3_ENDPOINT` value. |
| `3` | Credentials for the S3 storage are invalid, or the bucket/permissions are misconfigured. |
| `4` | No report was found. The TLSAssistant container failed to generate a PDF. |
| `5` | The OneGate CLI was not found or the context token is missing. Ensure the template has `TOKEN = "YES"` and OneGate is reachable. |
| `6` | The TLSAssistant container exited with an error. The original container exit code is reported in the error message. |

## Version History

See [CHANGELOG.md](appliances/tlsassistant/CHANGELOG.md) for detailed version history.

## Tool's Features

For detailed information on the analysis engine, visit the [official TLSAssistant repository](https://github.com/stfbk/tlsassistant).

## License

```
Copyright 2026, Fondazione Bruno Kessler

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

Developed within the [Security & Trust](https://st.fbk.eu/) research unit, part of the [Center for Cybersecurity](https://cs.fbk.eu/) at [Fondazione Bruno Kessler](https://www.fbk.eu/en/) (Italy)
