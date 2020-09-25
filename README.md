# VMware Data Collection Tool (vmware-data-collection)

Connects to vCenter and gathers information on ESXi servers as well as virtual machines.

## Install the dependencies
```bash
yarn
```

### Start the app in development mode (hot-code reloading, error reporting, etc.)
```bash
quasar dev
```

### Lint the files
```bash
yarn run lint
```

### Build the app for production
```bash
quasar build
```

### Customize the configuration
See [Configuring quasar.conf.js](https://quasar.dev/quasar-cli/quasar-conf-js).



# vmware-data-collection.ps1 Powershell usage

.\vmware-data-collection.ps1 -vcenter {host} -username {username} -password {password} -metricDays {int} -csv -anon

-csv : Returns results in json format to screen but also creates a csv file locally
-anon : Anonomizes the host and vm names within the results
