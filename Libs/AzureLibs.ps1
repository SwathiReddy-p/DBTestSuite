
function LogMsg([int]$level, [string]$msg, [string]$BackGround, [string]$ForeGround)  
{
<#
.Synopsis
    Write a message to the log file and the console.
.Description
    Add a time stamp and write the message to the test log.  In
    addition, write the message to the console.  Color code the
    text based on the level of the message.
.Parameter level
    Debug level of the message
.Parameter msg
    The message to be logged
.Example
    LogMsg 3 "This is a test"
#>

    if ($level -le $dbgLevel)
    {
        $now = [Datetime]::Now.ToString("MM/dd/yyyy HH:mm:ss : ")
        ($now + $msg) | out-file -encoding ASCII -append -filePath $logfile
		if ( $ForeGround -eq "" )
		{
			$ForeGround = "Gray"
			if ( $msg.StartsWith("Error"))
			{
				$ForeGround = "red"
			}
			elseif ($msg.StartsWith("Warn"))
			{
				$ForeGround = "Yellow"
			}
			elseif ($msg.StartsWith("Debug"))
			{
				$ForeGround = "Green"
			}
			else
			{
				$ForeGround = "White"
			}
		}
		if ($BackGround -ne "")
		{
			write-host -f $ForeGround -b $BackGround "$msg"
		}
		else
		{
			write-host -f $ForeGround "$msg"
		}
    }
}

<#
    Syntax:
    AzureRmVmPublicIP -ResourceGroupName $resourceGroupName -VMName $VMName
#>
Function Get-AzureRmVmPublicIP {
<#
    .SYNOPSIS
        Correlate AzureRM VMs, NetworkInterfaces, and Public IPs
    
    .DESCRIPTION
        Correlate AzureRM VMs, NetworkInterfaces, and Public IPs

        Prerequisites:
            
            * You have the AzureRM module
            * You're authenticated
            * You're running PowerShell 4 or later

    .PARAMETER ResourceGroupName
        Query this resource group

    .PARAMETER VMName
        One or more VM names to include.  Accepts wildcards.  Defaults to all.

    .PARAMETER IncludeObjects
        If specified, include VM, NIC, and PIP (Public IP) properties on each entry

    .PARAMETER VMStatus
        If specified, the VM property from IncludeObjects will include data from Get-AzureRmVm '-Status'

        Using this switch will trigger IncludeObjects

    .EXAMPLE
        Login-AzureRmAccount
        Get-AzureRmVmPublicIP -ResourceGroupName 'my-resource-group'

            # VMName  NICName    PublicIP
            # ------  -------    --------
            # VM-2    VM-2-NIC   23.96.1.2
            # VM-3    VM-3-NIC   23.96.1.3
            # VM-4    VM-4-NIC   168.61.2.1
            # VM-16   VM-16-NIC  168.61.10.27
            # VM-17   VM-17-NIC  23.96.17.56
            # VM-18   VM-18-NIC  23.96.19.71
            # VM-1    VM-1-NIC   Not Assigned

        # List VMs, NICS, and Public IPs in 'my-resource-group'

    .EXAMPLE
        Login-AzureRmAccount
        Get-AzureRmVmPublicIP -ResourceGroupName 'my-resource-group' -VMName VM-1* -IncludeObjects

            # ...
            # VMName   : VM-18
            # NICName  : VM-18-NIC
            # PublicIP : 23.96.19.71
            # VM       : Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine
            # NIC      : Microsoft.Azure.Commands.Network.Models.PSNetworkInterface
            # PIP      : Microsoft.Azure.Commands.Network.Models.PSPublicIpAddress

            # VMName   : VM-1
            # NICName  : VM-1-NIC
            # PublicIP : Not Assigned
            # VM       : Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine
            # NIC      : Microsoft.Azure.Commands.Network.Models.PSNetworkInterface
            # PIP      : Microsoft.Azure.Commands.Network.Models.PSPublicIpAddress

        # Get VMs, NICs, and Public IPs in 'my-resource-group'
        # with name like VM-1*
        # Include the VM, Network Interface (NIC), and Public IP (PIP) objects properties

    .EXAMPLE
        $Details = Get-AzureRmVmPublicIP -ResourceGroupName 'my-resource-group' -VMStatus
        $Details[0]

            # VMName   : VM-18
            # NICName  : VM-18-NIC
            # PublicIP : 23.96.19.71
            # VM       : Microsoft.Azure.Commands.Compute.Models.PSVirtualMachineInstanceView <<<<
            # NIC      : Microsoft.Azure.Commands.Network.Models.PSNetworkInterface
            # PIP      : Microsoft.Azure.Commands.Network.Models.PSPublicIpAddress

        # All sorts of data to explore in the VM property.  Output from Get-AzureRmVm -Name <ThisVm> -Status
        $Details[0].VM.VMAgent.ExtensionHandlers

            # Type                                        TypeHandlerVersion Status                                                      
            # ----                                        ------------------ ------                                                      
            # Microsoft.Azure.Diagnostics.IaaSDiagnostics 1.7.1.0            Microsoft.Azure.Management.Compute.Models.InstanceViewStatus
            # Microsoft.Compute.BGInfo                    2.1                Microsoft.Azure.Management.Compute.Models.InstanceViewStatus
            # Microsoft.Compute.CustomScriptExtension     1.8                Microsoft.Azure.Management.Compute.Models.InstanceViewStatus

    .EXAMPLE

        Get-AzureRmVmPublicIP -ResourceGroupName $ResourceGroup -VMName VM-18 -VMStatus |
        Select -Property VMName,
                            PublicIP,
                            @{ label = "PrivateIP"; expression = {$_.NIC.IpConfigurations.PrivateIpAddress} },
                            @{ label = "VMAgentStatus"; expression = {$_.VM.VMAgent.Statuses[0].DisplayStatus} }

            # VMName PublicIP    PrivateIP    VMAgentStatus
            # ------ --------    ---------    -------------
            # VM-18  23.96.19.71 10.1.2.5     Ready       

        # Pull details from VM-18,
        # extract private IP from the NIC, and the first VMAgent status we find from the VM

    .FUNCTIONALITY
        Azure
#>
    [cmdletbinding()]
    param(
        [string[]]$ResourceGroupName,
        [string[]]$VMName,
        [switch]$IncludeObjects,
        [switch]$VMStatus
    )

    foreach($ResourceGroup in $ResourceGroupName)
    {

        # Here's an absurd snippet of code to extract all VMs, NICs, and Public IPs, and correlate them together.
        # From what I can tell, the Azure team didn't provide the usual pipeline support...
        # This method will skip public IPs that aren't bound to a NIC, or NICs that aren't bound to a VM
        Try
        {
            $AllVMs = @( Get-AzureRMVm -ResourceGroupName $ResourceGroup -ErrorAction Stop )
        }
        Catch
        {
            Write-Error $_
            Write-Error "Could not extract VMs from resource group '$ResourceGroup'"
            continue
        }
        Try
        {
            $NICS = @( Get-AzureRmNetworkInterface -ResourceGroupName $ResourceGroup -ErrorAction Stop )
        }
        Catch
        {
            Write-Error $_
            Write-Error "Could not extract network interfaces from resource group '$ResourceGroup'"
            continue
        }
        Try
        {
            $PublicIPS = @( Get-AzureRmPublicIpAddress -ResourceGroupName $ResourceGroup -ErrorAction Stop)
        }
        Catch
        {
            Write-Error $_
            Write-Error "Could not extract public IPs from resource group '$ResourceGroup'"
            continue
        }

        # Allow wildcard support for each name in array... filter dupes
        $TheseVMs = foreach($VM in $AllVMs)
        {
            if($VMName)
            {
                foreach($Name in $VMName)
                {
                    if($VM.Name -like $Name)
                    {
                        $VM
                    }
                }
            }
            else
            {
                $VM
            }
        }
        $TheseVMs = @( $TheseVMs | Sort Name -Unique )

        # Correlate. Uses PS4 language.
        Foreach($nic in $nics)
        {
            $VMs = $null   
            $VMs = $TheseVMs.Where({$_.Id -eq $nic.virtualmachine.id})
            $PIPS = $null
            $PIPS = $PublicIPS.Where({$_.Id -eq $nic.IpConfigurations.publicipaddress.id})
            foreach($VM in $VMs)
            {
                if($VMStatus)
                {
                    Try
                    {
                        $VMDetail = Get-AzureRMVm -ResourceGroupName $ResourceGroup -Status -Name $VM.Name -ErrorAction stop
                    }
                    Catch
                    {
                        Write-Error $_
                        Write-Error "Could not extract '-Status' details from $($VM.Name) in resource group $ResourceGroup. Falling back to non detailed"
                        $VMDetail = $VM
                    }
                    if(-not $IncludeObjects)
                    {
                        $IncludeObjects = $True
                    }
                }
                else
                {
                    $VMDetail = $VM
                }

                foreach($PIP in $PIPS)
                {
                    # Include VM, NIC, Public IP (PIP) raw objects if desired
                    $Output = [ordered]@{
                        ResourceGroupName = $ResourceGroup
                        VMName = $VM.Name
                        NICName = $nic.Name
                        PublicIP = $PIP.IpAddress
                    }

                    if($IncludeObjects)
                    {
                        $Output.Add('VM', $VMDetail)
                        $Output.Add('NIC', $NIC)
                        $Output.Add('PIP', $PIP)
                    }

                    [pscustomobject]$Output
                }
            }
        }
    }
}

#GetVMDetails $VMDetails, $resourceGroupName, $VMName, $ParametersFile)
Function GetVMDetails
{
    [cmdletbinding()]
    Param (
        [Object[]] $RGDetails
    ) 
    LogMsg 0 "Info : Getting the Username, Password and IPAddress of the VM"
    
    $VMDetails = New-Object -TypeName PSObject -Property $VMproperties

    $VMParams = Get-Content $RGDetails.ParametersFile | ConvertFrom-Json
    $VMDetails.VMName = $VMParams.parameters.VMName.value
    $VMDetails.UserName = $VMParams.parameters.adminUsername.value
    $VMDetails.PassWord = $VMParams.Parameters.adminPassword.value
        
    $VMDetails.IP = (AzureRmVmPublicIP -ResourceGroupName $RGDetails.resourceGroupName -VMName $VMDetails.VMName).PublicIP

    return $VMDetails
}

function  LoginAzureAccount
{
    [cmdletbinding()]
    Param (
        [string] $subscriptionId = "UnDeclared"
    ) 
    # Sigining in to the Azure Account
    LogMsg 0 "Info : Logging into Azure Account"
    try {
        Login-AzureRmAccount
    }
    catch {
        LogMsg 0 "Error : Login failed"
        exit
    }
    LogMsg 0 "Info : Azure Login succesful!"
    
    if ($subscriptionId -ne "UnDeclared")
    {
        #Select subscription
        LogMsg 0 "Info : Select the subscription: $subscriptionId"
        Select-AzureRmSubscription -SubscriptionID $subscriptionId
    }
}
function VerifyAndCleanUpResourceGroup
{
    [cmdletbinding()]
    Param (
        [Object[]] $RGDetails,
        [switch] $DeleteIfExists = $False
    ) 
    # Create or using existing resourceGroup 
    LogMsg 0 "Info: Verifying if ResourceGroupName $($RGDetails.resourceGroupName) exists or not.."
    try {
        $resourcegroup = Get-AzureRmResourceGroup -Name $RGDetails.resourceGroupName -erroraction silentlycontinue
        if($resourcegroup)
        {
            LogMsg 5 "Debug: Resourcegroup: $($RGDetails.resourceGroupName) already exists"
            if ($DeleteIfExists)
            {
                LogMsg 0 "Warn: Deleting Resourcegroup: $($RGDetails.resourceGroupName) as '-DeleteIfExists' option is passed"
                Remove-AzureRmResourceGroup -Name $RGDetails.resourceGroupName -Force
                LogMsg 0 "Info: Deleting Resourcegroup: $($RGDetails.resourceGroupName) completed."
                
                LogMsg 0 "Info: Re-creating ResourceGroup: $($RGDetails.resourceGroupName) ..."
                New-AzureRmResourceGroup -Name $RGDetails.resourceGroupName -Location $RGDetails.location >$null 2>&1
                LogMsg 0 "Info: Re-creating ResourceGroup: $($RGDetails.resourceGroupName) done!"
            }
        }
        else {
            LogMsg 0 "Info: Creating ResourceGroup: $($RGDetails.resourceGroupName)"
            New-AzureRmResourceGroup -Name $RGDetails.resourceGroupName -Location $RGDetails.location >$null 2>&1               
        }
    }
    catch {
        LogMsg 0 "Info: Creating ResourceGroup: $($RGDetails.resourceGroupName)"
        New-AzureRmResourceGroup -Name $RGDetails.resourceGroupName -Location $RGDetails.location >$null 2>&1
    }
}

function CleanUpResourceGroup
{
    [cmdletbinding()]
    Param (
        [Object[]] $RGDetails
    ) 
    # Create or using existing resourceGroup 
    LogMsg 0 "Info : Removing ResourceGroupName $($RGDetails.resourceGroupName) .."
    try 
    {
        Remove-AzureRmResourceGroup -Name $RGDetails.resourceGroupName -Verbose -Force
        LogMsg 0 "Info : Deleting Resourcegroup: $($RGDetails.resourceGroupName) completed."
    }
    catch {
        LogMsg 0 "Info : Failed to delete ResourceGroup: $($RGDetails.resourceGroupName)"
    }
}

<#
#   Deploying VM and checking whether it is succeeded or not
#   Syntax GetRGDetails <TestName>
#>

function GetRGDetails 
{
    [cmdletbinding()]
    Param (
        [string] $TestName = "UnDeclared"
    )

    $RGDetails = New-Object -TypeName PSObject -Property $RGproperties
    
    $RGDetails.resourceGroupName = $resourceGroupName
    $RGDetails.subscriptionId = $subscriptionId

    $TestDefinitions = Get-Content "Templates\TestDefinitions.json" | ConvertFrom-Json
    LogMsg 5 "Debug: TestDefinitions : `n $($TestDefinitions | ConvertTo-Json)"

    $RGDetails.TestDetails = $TestDefinitions.TestDefinitions.$TestName
    LogMsg 5 "Debug: TestDetails : `n $($RGDetails.TestDetails | ConvertTo-Json)"

    if ($RGDetails.TestDetails)
    {
        $RGDetails.TemplateFile = $TestDefinitions.Templates.$TemplateType.TemplateFile
        $RGDetails.ParametersFile = $TestDefinitions.Templates.$TemplateType.ParametersFile
        LogMsg 5 "Debug: TemplateFile : $($RGDetails.TemplateFile)"
        LogMsg 5 "Debug: ParametersFile : $($RGDetails.ParametersFile)"
        if (-not $RGDetails.TemplateFile)
        {
            LogMsg 0 "Error: Unknown Test TemplateType: '$TemplateType'"
            exit
        }
        else {
            LogMsg 5 "Debug: Contents of ParametersFile : `n $(Get-Content $RGDetails.ParametersFile )"
        }    
    }
    else 
    {
        LogMsg 0 "Error: Unknown Test: '$TestName'"
        exit
    }

    # Creating temp Parameters file with given VM size
    if ( $RGDetails.ParametersFile -ne "UnDeclared" )
    {
        $VMParams = Get-Content $RGDetails.ParametersFile | ConvertFrom-Json
        $RGDetails.Location = $VMParams.parameters.location.value
        $RGDetails.VMName = $VMParams.parameters.VMName.value

        if ( $vmSize -ne "UnDeclared" )
        {
            $VMParams.parameters.vmSize.value = $vmSize
            $VMParams | ConvertTo-Json -depth 100 | Set-Content "$($LogFolder)\azuredeploy.parameters_temp.json"
            $RGDetails.ParametersFile = "$($LogFolder)\azuredeploy.parameters_temp.json"
        }
    }

    return $RGDetails
}

<#
#   Deploying VM and checking whether it is succeeded or not
#   Syntax DeploySingleVM $RGDetails
#>
Function DeploySingleVM
{
    [cmdletbinding()]
    Param (
        [Object[]] $RGDetails
    )

    LogMsg 0 "Info: Deploying the ResourceGroup '$($RGDetails.ResourceGroupName)'..."
    $RGdeployment = New-AzureRmResourceGroupDeployment -ResourceGroupName $RGDetails.ResourceGroupName -TemplateFile $RGDetails.TemplateFile -TemplateParameterFile $RGDetails.ParametersFile
    
    if ($RGdeployment.ProvisioningState -eq "Succeeded")
    {
        $MaxTimeOut=300
        $i=0
        while($MaxTimeOut -gt $i)
        {
            $vmStatus=Get-AzureRmVM -ResourceGroupName $RGDetails.ResourceGroupName -Name $RGDetails.vmName  -Status
            if($vmStatus.Statuses[0].DisplayStatus -eq  "Provisioning succeeded")
            {
                LogMsg 0 "Info: Deployment completed succesfully"
                break
            }
            else
            {
                <#
                    Warning: Don't use LogMsg here.
                #>
                Write-Host "." -NoNewline
            }
            $i=$i+1
        }

        if ($MaxTimeOut -eq $i)
        {
            LogMsg 0 "Error: Deployment failed"
        }       
    }    
}

function WaitTillMachineBoots 
{
    [cmdletbinding()]
    Param (
        [Object[]] $VMDetails
    ) 
    LogMsg 5 "Debug: Checking if VM is up:"
    for($count = 0; $count -le 30; $count++ )
    {
        $output = echo y | .\bin\plink.exe  -pw $VMDetails.PassWord -P 22 -l $VMDetails.UserName $VMDetails.IP "uptime" 2>&1
        $output = $output | Select-String -Pattern 'load average'

        if ( $output )
        {
            break
        }
        else
        {
            <#
                Warning: Don't use LogMsg here.
            #>            
            Write-Host "." -NoNewline  
        }
    }

    ""
    if ( $output )
    {
        LogMsg 5 "Debug: VM is up"
        return $true
    }
    else {
        LogMsg 5 "Debug: VM isn't up"
        return $false
    }    
}

function DownloadFilesAndLogs 
{
    [cmdletbinding()]
    Param (
        [Object[]] $VMDetails
    ) 
	$VMLogDownloadFolder = $(Join-Path $LogFolder $vm.vmName)

	If( -not (test-path $VMLogDownloadFolder))
	{
		New-Item -ItemType Directory -Force -Path $VMLogDownloadFolder | out-null
	}
    RunLinuxCmd -username $VMDetails.UserName -password $VMDetails.PassWord -ip $VMDetails.IP -port 22 -command "dmesg > dmesg.log"  -runAsSudo -ignoreLinuxExitCode
    RunLinuxCmd -username $VMDetails.UserName -password $VMDetails.PassWord -ip $VMDetails.IP -port 22 -command "cat /var/log/messages >  messages.log"  -runAsSudo -ignoreLinuxExitCode
    RunLinuxCmd -username $VMDetails.UserName -password $VMDetails.PassWord -ip $VMDetails.IP -port 22 -command "cat /var/log/syslog > syslog.log"  -runAsSudo -ignoreLinuxExitCode
     
	RemoteCopy -download -downloadFrom $VMDetails.IP -files "*" -downloadTo $VMLogDownloadFolder -port $VMDetails.Port -username $VMDetails.UserName -password $VMDetails.PassWord
}

<#
Upload files related to the test
Syntax:
    UploadFiles -VMDetails $VMDetails -RGDetails  $RGDetails 
#>
function UploadFiles
{
    [cmdletbinding()]
    Param (
        [Object[]] $VMDetails,
        [Object[]] $RGDetails
    ) 
    .\bin\dos2unix.exe .\LinuxScripts\* 2>&1  >$null
    $SupportFilesList = $RGDetails.TestDetails.SupportFiles -split ","
    $SupportFilesList = $RGDetails.TestDetails.TestScript + $SupportFilesList
    if ($SupportFilesList.count -ne 0 )
    {
        ForEach ( $File in $SupportFilesList )
        {
            LogMsg 5 "Debug: Uploading $File"
            RemoteCopy -uploadTo $VMDetails.IP -port $VMDetails.Port -files ".\LinuxScripts\$File" -username $VMDetails.UserName -password $VMDetails.PassWord -upload
        }
    }
    else 
    {
        LogMsg 5 "Debug: No file are uploaded as both 'SupportFiles' & 'TestScript' are empty"
    }
}

<#
Syntax:
    RunTestScript -VMDetails $VMDetails -RGDetails  $RGDetails
#>

function RunTestScript
{
    [cmdletbinding()]
    Param (
        [Object[]] $VMDetails,
        [Object[]] $RGDetails,
        [int16] $runMaxAllowedTime=500
    ) 
    RunLinuxCmd -username $VMDetails.UserName -password $VMDetails.PassWord -ip $VMDetails.IP -port $VMDetails.Port -command "bash $($RGDetails.TestDetails.TestScript) > ConsoleLogFile.log" -runAsSudo -runMaxAllowedTime $runMaxAllowedTime
}
<#
#   Script execution starts from here..
#>

$dbgLevel_Debug=10
$dbgLevel_Release=1
if ($Debug)
{
	$dbgLevel=$dbgLevel_Debug
}
else
{
	$dbgLevel=$dbgLevel_Release
}

function ValidateInputs 
{
    if ( $subscriptionId -eq "UnDeclared")
    {
        LogMsg 0 "Error: Please provide valid subscriptionId"
        Exit
    }
    
    if ( $TestName -eq "UnDeclared")
    {
        LogMsg 0 "Error: Please provide valid TestName"
        Exit
    }    
}

$WorkingDir=(Get-Item -Path ".\").FullName
$DateString=$((Get-Date).ToString('yyyy_MM_dd_hh_mm_ss'))
$LogDir="Logs\$DateString"
$LogFolder="$($WorkingDir)\$($LogDir)"
$logfile="$($LogFolder)\LocalLogFile.log"

New-Item -ItemType Directory -Force -Path $LogFolder | out-null

ValidateInputs

#
$RGproperties = @{  'subscriptionId' = "UnDeclared";
                    'resourceGroupName' = "UnDeclared";
                    'Location' = "UnDeclared";
                    'VMName' = "UnDeclared";
                    'TemplateFile' = "UnDeclared";
                    'ParametersFile' = "UnDeclared";
                    'TestDetails' = {}
                }

$VMproperties = @{  'IP'="UnDeclared";
                    'Port'=22;
                    'VMName'="UnDeclared";
                    'UserName'="UnDeclared";
                    'PassWord'="UnDeclared"
                }