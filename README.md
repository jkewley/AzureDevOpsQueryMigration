# AzureDevOpsQueryMigration
Migrate Azure DevOps work item queries from one organization to another


At Blue Chip Consulting Group, we are often brought in to help companies with mergers and acquisitions. Sometimes this means moving Azure DevOps projects from one tenant to another. 

There are several reliable tools to help with this type of work. The Azure DevOps Migation Tools project is a decent open source option which handles several key aspects of migration very well. Unfortunately, it's not well documented and requires a deep understanding of how to configure each task. OpsHub has a nice commercial offering which we've used with great success, but it focuses mostly on the migration of work items and expects core pieces such as areas, iterations, and user accounts to be set up ahead of time.

A recent engagement had a project with dozens of custom shared queries that needed to be migrated. I tried using the DevOps Migration Tool to accomplish this, but was unsuccessful after several tries so I went to the REST API documentation to see what it would take to write something myself. It turns out that the query and create payloads looked very similar, so I decided to roll my own solution.

I typically work in C#, but decided to go with PowerShell because of the dynamic handling of Json payloads that it offers. It was apparent from the documentation and some sample requests I tested in Postman that a recursive enumeration of the Get result would be easy to pipe into the target DevOps instance to create the queries in the target organization.

The script requires a few items to be in place before you run it

* The project name : the script assumes you're moving the queries to a project with the same name in the destination DevOps organization. If you're targeting a different instance it should be an easy tweak to the PowerShell script to introduce a different target project name
* The source and target organization names : These are the custom url segments that identify the organization and follow dev.visualstudio.com in the organization base url. This script will work even if you are using the old url format of <organization>.visualstudio.com.
* Personal Access Tokens for each organization : The source organization requires Work Item Read and the target organization required Work Item Read/Write. Here's an article that shows how to create a PAT in your DevOps instance.

You'll want to set up areas and iterations in the target organization before running this script if your queries depend on them. DevOps Migration Tools handles this well if you enable the NodeStructuresMigrationConfig processor. Doing so is as easy as using these settings for the configuration.json:
```
 "Processors": [
    {
        "ObjectType": "VstsSyncMigrator.Engine.Configuration.Processing.NodeStructuresMigrationConfig",
        "PrefixProjectToNodes": false,
        "Enabled": true
    },
    …
 ]
 ```
And that's it. The script can be executed multiple times. It'll skip queries with the same name and folder hierarchy location in the destination organization.