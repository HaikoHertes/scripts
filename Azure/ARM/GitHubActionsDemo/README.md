Hier findet ihr die ARM-templates und das Workflow YML file zu meinem YouTube Video für GitHub Actions.

**Als Aufruf für das Anlegen des Service Principals habe ich verwendet:**

`az ad sp create-for-rbac --name "githubactions" --role contributor --scopes /subscriptions/<SUB_ID> --sdk-auth`

**Bei Bedarf könnt ihr euch das Repo auch gerne direkt von hier ziehen:**

https://github.com/HaikoHertes/ActionsDemo
