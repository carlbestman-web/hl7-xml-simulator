# HL7 to SLB XML Simulator — GitHub Pages Edition

This is a browser-only conversion of the Spring Boot `HL7 XML Simulator v2`.
It supports the same ORM New Order baseline and does not need Java, Node.js,
IntelliJ, a VM, or a backend server.

## Scope

- Parses HL7 segments and fields in the browser.
- Retrieves `CHRG_SLB_COMPOUND_ID` by matching OBX-3.1 and reading OBX-5.
- Produces the same baseline SLB XML structure as the Spring Boot version.
- The temporary `<study_only_generic_supplies>` block remains a study element;
  it is not an approved SLB XML element.
- DFT, RDE, ActiveQ, database connectivity, and production interfaces are not included.

## Privacy and security

The application has no backend and makes no network request with the HL7 input.
Processing occurs in the user's browser. Use synthetic or formally approved test
data only. Never commit real HL7 messages or patient information to GitHub.

## Publish through GitHub Pages

1. Create a new GitHub repository named `hl7-xml-simulator`.
2. Select **Public** if your GitHub plan does not support Pages for private repositories.
3. Do not initialize it with a README because this package already includes one.
4. Extract the upload ZIP on your computer.
5. In the empty repository, select **uploading an existing file**.
6. Upload these root files: `index.html`, `app.js`, `styles.css`, and `README.md`.
7. Enter `Add GitHub Pages simulator` as the commit message and commit to `main`.
8. Open **Settings > Pages**.
9. Under **Build and deployment**, choose **Deploy from a branch**.
10. Select branch **main**, folder **/(root)**, and click **Save**.
11. Wait for GitHub to show **Your site is live**.

The expected URL is:

`https://YOUR-USERNAME.github.io/hl7-xml-simulator/`

For the repository owner shown in the supplied screenshot, the expected URL is:

`https://carlbestman-web.github.io/hl7-xml-simulator/`

## Whitelisting request

Ask the approving team to permit HTTPS access to:

- Exact application URL: `https://carlbestman-web.github.io/hl7-xml-simulator/`
- Hostname, if their proxy uses domain rules: `carlbestman-web.github.io`
- TCP port: `443`

GitHub Pages uses HTTPS. The repository contains only static HTML, CSS, and
JavaScript; there is no server-side Java or Node.js process.

## Local verification without installation

Open `index.html` in a modern browser. The transformation should work without
installing any software. Clipboard access may require the published HTTPS site.

## Updating the site

Upload replacements for the changed files and commit them to `main`. GitHub
Pages will redeploy automatically. Do not upload the ZIP itself as the website;
upload the extracted files so `index.html` is in the repository root.
