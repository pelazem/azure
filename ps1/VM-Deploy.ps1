﻿# ##############################
# Purpose: Deploy RM VM - Managed Disks
#
# Author: Patrick El-Azem
#
# Notes: this script assumes you have created RGs, VNets, subnets, NSGs. It does create the availability set you designate, if it doesn't exist yet.
# ##############################

# Arguments with defaults
param
(
    [string]$SubscriptionId = '',
    [string]$Location = '',

    [string]$ResourceGroupNameVNet = '',
    [string]$VNetName = '',

    [string]$SubnetName = '',

    [string]$NSGName = '',

    [string]$ResourceGroupNameVM = '',

    [string]$AvailabilitySetName = '',
    [int]$FaultDomainCount = 3,
    [int]$UpdateDomainCount = 5,
    [bool]$AvailabilitySetIsManaged = $true,

    [string]$VMName = '',
    [string]$VMSize = '',

    [string]$OsDiskSkuName = 'PremiumLRS',
    [string]$OsTypeName = 'Windows',
    [string]$OsDiskFileNameTail = '_os',
    [int]$OSDiskSizeInGB = 128,

    [string]$DataDiskSkuName = 'PremiumLRS',
    [string]$DataDiskFileNameTail = '_data_',
    [int]$DataDiskSizeInGB = 256,
    [int]$NumberOfDataDisks = 0,

    [bool]$UsePublicIP = $true,
    [string]$PIPName1 = $VMName + '_pip_1',
    [string]$NICName1 = $VMName + '_nic_1',

    [string]$VMPublisherName = 'MicrosoftWindowsServer',
    [string]$VMOffer = 'WindowsServer',
    [string]$VMSku = '2016-Datacenter',
    [string]$VMVersion = 'latest',

    [string]$ResourceGroupNameDiagnostics = '',
    [string]$StorageAccountNameDiagnostics = '',
    [string]$AppInsightsInstrumentationKey = ''
)

$credPromptText = 'Type the name and password of the VM local administrator account.'

# Ensure diagnostics storage account exists
$diagsa = .\StorageAccount-CreateGet.ps1 -ResourceGroupName $ResourceGroupNameDiagnostics -Location $Location -StorageAccountName $StorageAccountNameDiagnostics -StorageAccountSkuName 'Standard_LRS'

# Get VNet
$vnet = Get-AzureRmVirtualNetwork -Name $VNetName -ResourceGroupName $ResourceGroupNameVNet

# Get subnet
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -VirtualNetwork $vnet -Name $SubnetName


if ($UsePublicIP -eq $true)
{
    # Get public IP
    $pip1 = New-AzureRmPublicIpAddress -Name $PIPName1 -ResourceGroupName $ResourceGroupNameVM -Location $Location -AllocationMethod Dynamic

    # Get NIC
    $nic1 = New-AzureRmNetworkInterface -Name $NICName1 -ResourceGroupName $ResourceGroupNameVM -Location $Location -SubnetId $subnet.Id -PublicIpAddressId $pip1.Id
}
else
{
    # Get NIC without public IP - private IP only
    $nic1 = New-AzureRmNetworkInterface -Name $NICName1 -ResourceGroupName $ResourceGroupNameVM -Location $Location -SubnetId $subnet.Id
}

# Set the private IP to static rather than dynamic
$nic1.IpConfigurations[0].PrivateIpAllocationMethod = 'Static'
Set-AzureRmNetworkInterface -NetworkInterface $nic1


# Get credential
$cred = Get-Credential -Message $credPromptText


if ($AvailabilitySetName)
{
    # Get availability set - create if not exists
    $avset = .\AvailabilitySet-CreateGet.ps1 -ResourceGroupName $ResourceGroupNameVM -Location $Location -AvailabilitySetName $AvailabilitySetName -FaultDomains $FaultDomainCount -UpdateDomains $UpdateDomainCount -Managed $AvailabilitySetIsManaged

    $vm = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize -AvailabilitySetId $avset.Id
}
else
{
    $vm = New-AzureRmVMConfig -VMName $VMName -VMSize $VMSize
}

$vm = Set-AzureRmVMOperatingSystem -VM $vm -Windows -ComputerName $VMName -Credential $cred -ProvisionVMAgent -EnableAutoUpdate

$vm = Set-AzureRmVMSourceImage -VM $vm -PublisherName $VMPublisherName -Offer $VMOffer -Skus $VMSku -Version $VMVersion

# Add NIC
$vm = Add-AzureRmVMNetworkInterface -VM $vm -Id $nic1.Id -Primary

# Add OS disk
$diskNameOS = ($VMName + $OsDiskFileNameTail)
$vm = Set-AzureRmVMOSDisk -Windows -VM $vm -CreateOption FromImage -Name $diskNameOS -DiskSizeInGB $OSDiskSizeInGB -StorageAccountType $OsDiskSkuName

# Add data disks
for ($ddi = 1; $ddi -le $NumberOfDataDisks; $ddi++)
{
    $diskNameData = ($VMName + $DataDiskFileNameTail + $ddi)
    $vm = Add-AzureRmVMDataDisk -VM $vm -Lun $ddi -CreateOption Empty -DiskSizeInGB $DataDiskSizeInGB -Name $diskNameData -StorageAccountType $DataDiskSkuName
}

# Create the VM with its disks
New-AzureRmVM `
    -ResourceGroupName $ResourceGroupNameVM `
    -Location $Location `
    -VM $vm | Out-Null

# Add diagnostics
.\VM-AddDiagnostics.ps1 -SubscriptionId $SubscriptionId -Location $Location -ResourceGroupNameDiagnostics $ResourceGroupNameDiagnostics -StorageAccountNameDiagnostics $StorageAccountNameDiagnostics -ResourceGroupNameVM $ResourceGroupNameVM -VMName $VMName -AppInsightsInstrumentationKey $AppInsightsInstrumentationKey

return $vm