# Azure Resource Manager post-deployment scripts

This a repo for shell scripts which can be run in the process of deploying an Azure resource using an ARM template.

Example `resource` from an ARM template.

```
{

    "type": "Microsoft.Compute/virtualMachines/extensions",
    "name": "[concat(parameters('vmName'), '/CustomScriptExtension')]",
    "apiVersion": "2023-07-01",
    "location": "[parameters('location')]",
    "dependsOn": [
        "[concat('Microsoft.Compute/virtualMachines/', parameters('vmName'))]"
    ],
    "properties": {
        "publisher": "Microsoft.Azure.Extensions",
        "type": "CustomScript",
        "typeHandlerVersion": "2.1",
        "autoUpgradeMinorVersion": true,
        "protectedSettings": {
            "fileUris": [
                "https://raw.githubusercontent.com/Phil-Jensen/arm-deployment-scripts/refs/heads/main/find-and-mount.sh"
            ],
            "commandToExecute": "sh find-and-mount.sh"
        }
    }
},
```

ref: https://learn.microsoft.com/en-us/azure/virtual-machines/extensions/custom-script-linux
