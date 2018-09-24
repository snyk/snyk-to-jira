[![Snyk logo](https://snyk.io/style/asset/logo/snyk-print.svg)](https://snyk.io)

***

# Snyk JSON to JIRA
The Snyk JSON to JIRA script takes the output of `synk test --json` and opens JIRA bugs with appropriate severity and titles. The description links back to the vulnDB for more information.

The script uses two JIRA custom fields to record the vulnID and the path, and does not recreate tickets if one already exists with same vulnID path.

# How do I use it?

### 1. Add custom fields to your JIRA project

  You'll need two custom fields setup for relevant Snyk metadata. (You can setup a custom field in JIRA by going to Settings --> Issues --> Custom Fields --> Add Custom Field).

  The two fields you'll need are (you can also customize these field names within the `snyk_to_jira.sh` script):

  - `snyk-vuln-id` This should be a "Text Field Single Line"
  - `snyk-path` This should be a "Text Field Single Line"


### 2. Rename the provided [`.jirarc`](jirarc-template.txt) template to `.jirarc`, populate the variables and place it in your project directory.

  ```
  mv "jirac-template.txt" ".jirarc"
  ```

  In the `.jirarc` file, you will need to set three variables:

  - `JIRA_USER` A valid user for your JIRA project
  - `JIRA_PASSWORD` The password for the provided user
  - `BASE_JIRA_URL` A URL pointing to the JIRA instance
  - `JIRA_PROJECT_NAME` The name of the JIRA project where you would like vulnerability bugs filed

### 3. Run the script by passing the results of `snyk test --json`

  ```
  cd ~/project
  snyk test --json > snyk_test.json
  snyk_to_jira.sh snyk_test.json
  ```

### 4. Open your JIRA project and triage away!

## License

[License: Apache License, Version 2.0](LICENSE)