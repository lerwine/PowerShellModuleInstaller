Param(
    [Alias("M")]
    [Parameter(Mandatory=$false)]
    [string]$Module,
    
    [Alias("U")]
    [Parameter(Mandatory=$false)]
    [switch]$Uninstall,
    
    [Alias("I")]
    [Parameter(Mandatory=$false)]
    [switch]$Install,
    
    [Alias("F")]
    [Parameter(Mandatory=$false)]
    [switch]$Force,
    
    [Alias("P")]
    [Parameter(Mandatory=$false)]
    [string]$ModuleInstallPath,
    
    [Alias("H", "?")]
    [Parameter(Mandatory=$false)]
    [switch]$Help,
    
    [Alias("X", "??")]
    [Parameter(Mandatory=$false)]
    [switch]$ExtendedHelp,
    
    [Alias("S")]
    [Parameter(Mandatory=$false)]
    [switch]$SystemWide,
    
    [Alias("C")]
    [Parameter(Mandatory=$false)]
    [switch]$CurrentUser,
    
    [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
    [string[]]$RemainingParameters = @()
)

function Write-StdErr {
    Param (
        [parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [object[]] $InputObjects
    )
    
    $outFunc = if ($Host.Name -eq 'ConsoleHost') { 
        [Console]::Error.WriteLine
    } else {
        $host.ui.WriteErrorLine
    }
    
    foreach ($obj in $InputObjects) {
        if ($obj -ne $null) {
            if (-not ($obj -is [string])) { $obj = $obj | Out-String }
            $outFunc.Invoke($obj);
        }
    }
}

function Write-LastError {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$false)]
        [switch]$Remove = $false
    )
    
    if ($Error.Count -gt 0) {
        $e = $Error[0];
        if ($Remove) { $e.RemoveAt(0) };
        Write-StdErr $e;
    }
}

function Get-UniqueValues {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string[]]$Values,
        
        [Parameter(Mandatory=$false)]
        [switch]$CaseSensitive = $false
    )
    
    $result = @();
    
    $compareFunc = $null;
    
    if ($CaseSensitive) {
        $compareFunc = {
            Param(
                [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
                [AllowNull()]
                [string]$Value
            )
            
            return (($result | Where-Object { $_ -ceq $Value }).Length -eq 0);
        };
    } else {
        $compareFunc = {
            Param(
                [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
                [AllowNull()]
                [string]$Value
            )
            
            return (($result | Where-Object { $_ -ieq $Value }).Length -eq 0);
        };
    }
    foreach ($str in $Values) {
        if ($str | &$compareFunc) { $result = $result + $str }
    }
    
    return [string[]]$result;
}

function Get-ValuesWithOuterBlanksTrimmed {
    [CmdletBinding()]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [string[]]$Values,
        
        [Parameter(Mandatory=$false)]
        [switch]$UseTrimmedValues = $false
    )
    
    $firstNonBlankIndex = $null;
    $lastNonBlankIndex = 0;
    
    for ($i = 0; $i -lt $Values.Length; $i++) {
        if ($Values[$i] -eq $null) { Continue; }
        if ($UseTrimmedValues) {
            if ($Values[$i].Trim().Length -eq 0) { Continue; }
        } else {
            if ($Values[$i].Length -eq 0) { Continue; }
        }
        
        $lastNonBlankIndex = $i;
        if ($firstNonBlankIndex -eq $null) { $firstNonBlankIndex = $i }
    }
    
    if ($firstNonBlankIndex -eq $null) { Return [string[]]@(); }
    
    if ($firstNonBlankIndex -eq 0 -and $lastNonBlankIndex -eq ($Values.Length - 1)) { return $Values }
    
    if ($firstNonBlankIndex -eq $lastNonBlankIndex) { return [string[]]@($Values[$firstNonBlankIndex]) }
    
    return [string[]]$Values[$firstNonBlankIndex..$lastNonBlankIndex];
}

function ConvertTo-StringArray {
    [CmdletBinding(DefaultParameterSetName="TrimLines")]
    Param(
        [Parameter(Mandatory=$true, ValueFromPipeline=$true)]
        [AllowNull()]
        [object]$InputObject,
        
        [Parameter(Mandatory=$false)]
        [string]$SubArrayJoinString = '',
        
        [Parameter(Mandatory=$false, ParameterSetName="TrimPartOfLine")]
        [switch]$TrimStartOfLines,
        
        [Parameter(Mandatory=$false, ParameterSetName="TrimPartOfLine")]
        [switch]$TrimEndOfLines,
        
        [Parameter(Mandatory=$false, ParameterSetName="TrimLines")]
        [switch]$TrimLines
    )
    
    if ($InputObject -eq $null -or ($InputObject -is [Array] -and $InputObject.Length -eq 0)) { Return @() }
    
    $result = $InputObject | ForEach-Object -Process:{
        $s = $_;
        if ($s -eq $null) {
            $s = '';
        } elseif ($s -is [Array]) {
            $s = ([string]($s -Join $SubArrayJoinString));
        } elseif (-not ($s -is [string])) {
            $s = $s.ToString()
        }
        
        if ($PsCmdlet.ParameterSetName -eq "TrimLines") {
            if ($TrimLines) { $s = $s.Trim(); }
        } else {
            if ($TrimStartOfLines) { $s = $s.TrimStart(); }
            if ($TrimEndOfLines) { $s = $s.TrimEnd(); }
        }
        
        $s;
    };
    
    if ($result -is [Array]) { return [string[]]$result }
    
    return [string[]]@($result);
}

function Get-InputFromUser {
    [CmdletBinding(DefaultParameterSetName="FreeForm")]
    Param(
        [Parameter(Mandatory=$true)]
        [string[]]$PromptLines,
        
        [Parameter(Mandatory=$true, ParameterSetName="Choices")]
        [hashtable]$ValidResponses,
        
        [Parameter(Mandatory=$false)]
        [string[]]$PromptResponseSeparator = '> ',
        
        [Parameter(Mandatory=$false, ParameterSetName="Choices")]
        [switch]$CaseSensitive,
        
        [Parameter(Mandatory=$false, ParameterSetName="Choices")]
        [switch]$EnumerateChoicesInPrompt,
        
        [Parameter(Mandatory=$false, ParameterSetName="Choices")]
        [string]$HelpChoice = $null,
        
        [Parameter(Mandatory=$false, ParameterSetName="Choices")]
        [hashtable]$AlternateResponseMapping = @{ },
        
        [Parameter(Mandatory=$false, ParameterSetName="FreeForm")]
        [switch]$AllowEmptyResponse,
        
        [Parameter(Mandatory=$false)]
        [switch]$NonInteractiveRecommendedAction = 'Run script in interactive mode'
    )
    
    if (-not [Environment]::UserInteractive) {
        $RecommendedAction = 'Run installer in interactive mode';
        if ($NonInteractiveRecommendedAction.Trim().Length -gt 0) {
            $RecommendedAction = $RecommendedAction + ' or ' + $NonInteractiveRecommendedAction.Trim();
        }
        
        Write-Error -Message:"Unable to get input from user. Script is being run in non-interactive mode." `
            -Category:'ReadError' -ErrorId:"InputRequired" -TargetObject $PromptLines -CategoryActivity 'Get-InputFromUser' `
            -CategoryReason:'[Environment]::UserInteractive set to $true' -CategoryTargetType [string[]] -RecommendedAction:$RecommendedAction;
        return;
    }
    
    $ResponseMapping = @{ };
    
    $addResponseMapping = {
        Param(
            [Parameter(Mandatory=$true)]
            [AllowEmptyString()]
            [string]$Key,
            
            [Parameter(Mandatory=$true)]
            [AllowNull()]
            [object]$ResponseDescription
        )
        
        $ResponseDescription = $ResponseDescription | ConvertTo-StringArray -TrimEndOfLines | Get-ValuesWithOuterBlanksTrimmed;
        
        $trimmedKey = $trimmedKey.Trim();
        
        $alternateResponses = [string[]]@($trimmedKey);
        
        if ($AlternateResponseMapping.ContainsKey($Key)) {
            $alternateResponses = [string[]]($alternateResponses + ($AlternateResponseMapping[$Key] | ConvertTo-StringArray -TrimLines));
        }
        
        if ($trimmedKey.Length -ne $Key.Length) {
            if ($AlternateResponseMapping.ContainsKey($trimmedKey)) {
                $alternateResponses = [string[]]($alternateResponses + ($AlternateResponseMapping[$trimmedKey] | ConvertTo-StringArray -TrimLines));
            }
        }
        
        if ($ResponseMapping.ContainsKey($trimmedKey)) {
            $alternateResponses = [string[]]($ResponseMapping[$trimmedKey]["Values"] + $alternateResponses);
            
            if ($ResponseMapping[$trimmedKey]["ResponseDescription"].Length -gt 0 -and $ResponseDescription.Length -gt 0) {
                $ResponseDescription = $ResponseDescription + '';
            }
            
            $ResponseDescription = [string[]]($ResponseDescription + $ResponseMapping[$trimmedKey]["ResponseDescription"]);
        }
        
        if ($CaseSensitive) {
            $alternateResponses = $alternateResponses | Get-UniqueValues -CaseSensitive;
        } else {
            $alternateResponses = $alternateResponses | Get-UniqueValues;
        }
        
        if ($alternateResponses.Length -eq 0) { $alternateResponses = [string[]]@($trimmedKey) }
        
        $alternateResponses = $alternateResponses | Where-Object {
                if (&{ if ($CaseSensitive) { $_ -ceq $trimmedKey } else { $_ -ieq $trimmedKey } }) { return $true }
                if ($ResponseMapping.ContainsKey($_)) { return $false }
                
                $altKey = $_;
                return (($ResponseMapping.Keys | Where-Object {
                    if (&{ if ($CaseSensitive) { $_ -ceq $trimmedKey } else { $_ -ieq $trimmedKey } }) { return $false }
                    $ResponseMapping[$_]["Values"] | Where-Object { if ($CaseSensitive) { $_ -ceq $altKey } else { $_ -ieq $altKey } }
                }).Length -eq 0);
            };
        
        if ($ResponseMapping.ContainsKey($trimmedKey)) {
            $ResponseMapping[$trimmedKey]["Values"] = $alternateResponses;
            $ResponseMapping[$trimmedKey]["ResponseDescription"] = $ResponseDescription;
        } else {
            $ResponseMapping.Add($trimmedKey, @{
                Values = $alternateResponses;
                ResponseDescription = $ResponseDescription;
            });
        }
    };
    
    foreach ($k in $ValidResponses.Keys) {
        &$addResponseMapping -Key:$k -ResponseDescription:$ValidResponses[$k];
    }
    
    if ($HelpChoice -ne $null -and -not $ResponseMapping.ContainsKey($HelpChoice)) {
        &$addResponseMapping -Key:$HelpChoice -ResponseDescription:'Show Help';
    }
    
    $getChoicesHelp = {
        $lines = @('Valid Choices (without quotes):');
        foreach ($k in $ResponseMapping.Keys) {
            $responseDescription = $ResponseMapping[$k]["ResponseDescription"];
            $values = $ResponseMapping[$k]["Values"]
            $firstLine = '';
            if (.Length -gt 0) { $firstLine = ' = ' + $responseDescription[0] }
            $lines = $lines + ([string]($values -join '"; "') + $firstLine);
            if ($responseDescription.Length -gt 1) {
                $lines = $lines + ($responseDescription[1..($responseDescription.Length - 1)] | ForEach-Object { "`t$_" })
            }
        }
        
        return [string[]]$lines;
    };

    $showHelp = $false;
    $response = $null;
    
    while ($response -eq $null) {
        $promptText = ($PromptLines -join "`n`t").Trim();
        if ($PsCmdlet.ParameterSetName -eq "Choices") {
            if ($showHelp) {
                $showHelp = $false;
                $s = (&$getChoicesHelp -join "`n").Trim();
                if ($promptText.Length -gt 0 -and $s.Length -gt 0) {
                    $promptText = "$s`n`n$promptText";
                } else {
                    $promptText = "$s$promptText";
                }
            } elseif ($EnumerateChoicesInPrompt) {
                $s = (&$getChoicesHelp -join "`n").Trim();
                if ($promptText.Length -gt 0 -and $s.Length -gt 0) {
                    $promptText = "$promptText`n`n$s";
                } else {
                    $promptText = "$promptText$s";
                }
            }
        }
        
        $response = Read-Host -Prompt $promptText + $PromptResponseSeparator | %{ if ($_ -eq $null) { '' } else { $_ } };
        
        if ($PsCmdlet.ParameterSetName -eq "Choices") {
            $response = $response.Trim();
            $matching = $ResponseMapping.Keys | Where-Object { ($ResponseMapping[$_]["Values"] | Where-Object { if ($CaseSensitive) { $_ -ceq $response } else { $_ -ieq $response } }).Length -gt 0; };
            if ($matching.Length -eq 0) {
                Write-Warning 'Invalid response';
                $response = $null;
                continue;
            }
            
            if ($HelpChoice -ne $null -and (&{ if ($CaseSensitive) { $HelpChoice -ceq $response } else { $HelpChoice -ieq $response } })) {
                $showHelp = $true;
                continue;
            }
            
            $response = $ResponseMapping[$matching[0]]["OriginalKey"];
        } else {
            if ($response.Trim().Length -eq 0 -and -not $AllowEmptyResponse) { $response = $null; continue; }
        }
    }
    
    return $response;
}

function ParseScopeParameters {
    [CmdletBinding(DefaultParameterSetName="CurrentUser")]
    Param(
        [Parameter(Mandatory=$true, ParameterSetName="SystemWide")]
        [switch]$SystemWide,
        
        [Parameter(Mandatory=$false, ParameterSetName="CurrentUser")]
        [switch]$CurrentUser = -not $SystemWide,
    
        [Parameter(Mandatory=$false)]
        [string]$Module,
        
        [Parameter(Mandatory=$false)]
        [switch]$Uninstall,
        
        [Parameter(Mandatory=$false)]
        [switch]$Install,
        
        [Parameter(Mandatory=$false)]
        [switch]$Force,
        
        [Parameter(Mandatory=$false)]
        [string]$ModuleInstallPath,
        
        [Parameter(Mandatory=$false)]
        [switch]$Help,
        
        [Parameter(Mandatory=$false)]
        [switch]$ExtendedHelp,
    
        [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
        [string[]]$RemainingParameters = @()
    )
    
    return @{ InstallSystemWide = -not $CurrentUser; RemainingParameters = $RemainingParameters };
}

function ParseInstallParameters {
    [CmdletBinding(DefaultParameterSetName="Install")]
    Param(
        [Parameter(Mandatory=$false)]
        [string]$Module = $null,
        
        [Parameter(Mandatory=$true, ParameterSetName="Uninstall")]
        [switch]$Uninstall,
        
        [Parameter(Mandatory=$false, ParameterSetName="Install")]
        [switch]$Install = -not $Uninstall,
        
        [Parameter(Mandatory=$false, ParameterSetName="Install")]
        [switch]$Force = $false,
        
        [Parameter(Mandatory=$false)]
        [string]$ModuleInstallPath = $null,
        
        [Parameter(Mandatory=$false)]
        [switch]$Help = $false,
        
        [Parameter(Mandatory=$false)]
        [switch]$ExtendedHelp = $false,
        
        [Parameter(Mandatory=$false)]
        [switch]$SystemWide,
        
        [Parameter(Mandatory=$false)]
        [switch]$CurrentUser,
        
        [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
        [string[]]$RemainingParameters = @()
    )
    
    $result = ParseScopeParameters @PSBoundParameters;
    
    $result.Add("ModuleName", $Module);
    $result.Add("Uninstall", -not $Install);
    $result.Add("Force", $Force);
    $result.Add("ModuleInstallationRootPath", $ModuleInstallPath);
    $result.Add("ShowHelp", $Help -or $ExtendedHelp);
    $result.Add("ShowExtendedHelp", $ExtendedHelp);
    
    return $result;
}

function ValidateParameters {
    Param(
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [string]$ModuleName,
        [Parameter(Mandatory=$true)]
        [boolean]$InstallSystemWide,
        [Parameter(Mandatory=$true)]
        [boolean]$Uninstall,
        [Parameter(Mandatory=$true)]
        [boolean]$Force,
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [boolean]$ModuleInstallationRootPath,
        [Parameter(Mandatory=$true)]
        [boolean]$ShowHelp,
        [Parameter(Mandatory=$true)]
        [boolean]$ShowExtendedHelp
    )
    
    $result = @{
        ModuleName = $ModuleName;
        InstallSystemWide = $InstallSystemWide;
        Uninstall = $Uninstall;
        Force = $Force;
        ModuleInstallationRootPath = $ModuleInstallationRootPath;
        ShowHelp = $ShowHelp;
        ShowExtendedHelp = $ShowExtendedHelp;
    };
    
    if ($ShowExtendedHelp) { $result["ShowHelp"] = $true }
    
    if ($ModuleName -eq $null -and -not $ShowHelp) {
        $installText = "Install";
        if ($Uninstall) { $installText = "Uninstall" }
        
        $prevEap = $ErrorActionPreference;
        $ErrorActionPreference = 'Stop';
        try {
            $ModuleName = (Get-InputFromUser -PromptLines:"Please provide the name of the module you wish to $installText (enter nothing to cancel)" -AllowEmptyResponse `
                -NonInteractiveRecommendedAction:'Run the installer in interactive mode or specify the -Module parameter') | %{ if ($_ -eq $null) { '' } else { $_.Trim() } };
                
            if ($ModuleName.Length -eq 0) {
                $result["ModuleName"] = $null;
                Write-StdErr "Module name must be provided";
                $result["ShowHelp"] = $true;
            } else {
                $result["ModuleName"] = $ModuleName;
            }
        } catch {
            Write-LastError -Remove;
            $result["ShowHelp"] = $true;
            $result["ModuleName"] = $null;
        } finally {
            $ErrorActionPreference = $prevEap;
        }
    } else {
        if ($ModuleInstallationRootPath -ne $null) {
            if ($ModuleName.Trim() -ieq (Split-Path -Path:$ModuleInstallationRootPath -Leaf)) {
                $prevEap = $ErrorActionPreference;
                $ErrorActionPreference = 'Stop';
                try {
                    $response = Get-InputFromUser -PromptLines:("The folder for the module installation root path has the same name as the module.`n" + `
                        "Typically, you would provide the root path to which modules are to be installed into their own self-named folders.`n" + `
                        "Do you want to use the parent folder as the installation root?") -ValidResponses:@{ Y="Yes"; N="No"; } -EnumerateChoicesInPrompt -AlternateResponseMapping:@{ Y="Yes"; N="No"; } `
                        -NonInteractiveRecommendedAction:'Run the installer in interactive mode or specify the -Path parameter';
                    
                    if ($response -eq 'Y') {
                        $ModuleInstallationRootPath = Split-Path -Path:$ModuleInstallationRootPath -Container;
                        $result["ModuleInstallationRootPath"] = $ModuleInstallationRootPath;
                    } else {
                        Write-StdErr "Name of installation folder cannot have the same name as the module.`nRather, this must point to the root folder where the module should be installed.";
                        $result["ShowHelp"] = $true;
                    }
                } catch {
                    Write-LastError -Remove;
                    $result["ShowHelp"] = $true;
                } finally {
                    $ErrorActionPreference = $prevEap;
                }
            }
        }
    }
    
    if ($ModuleInstallationRootPath -ne $null) {
        if (-not (Test-Path -Path:$ModuleInstallationRootPath -PathType:Container)) {
            if (Test-Path -Path:$ModuleInstallationRootPath -PathType:Leaf) {
                Write-StdErr "Path '$ModuleInstallationRootPath' does not point to a folder. Rather, it points to a file.";
            } else {
                Write-StdErr "Path '$ModuleInstallationRootPath' does not exist";
            }
            $result["ShowHelp"] = $true;
            $result["ModuleInstallationRootPath"] = $null;
        }
    } else {
        $result["ModuleInstallationRootPath"] = &{
            if ($InstallSystemWide) {
                $path = [System.IO.Path]::Combine($PSHome, "Modules");
                if (-not (Test-Path -Path:$path -PathType:Container)) {
                    Write-StdErr "PowerShell System Module folder '$path' does not exist";
                    $result["ShowHelp"] = $true;
                    return $null;
                }
                
                return $path;
             }
             
            $path = [System.Environment]::GetFolderPath('MyDocuments');
            if (-not (Test-Path -Path:$path -PathType:Container)) {
                Write-StdErr "User documents folder '$path' does not exist";
                $result["ShowHelp"] = $true;
                return $null;
            }
            
            $path = Join-Path -Path:$path -ChildPath:'WindowsPowerShell';
            if (-not (Test-Path -Path:$path -PathType:Container)) {
                if (Test-Path -Path:$ModuleInstallationRootPath -PathType:Leaf) {
                    Write-StdErr "Path '$path' does not point to a folder. Rather, it points to a file.";
                    $result["ShowHelp"] = $true;
                    return $null;
                }
                
                $folder = $null;
                
                try {
                    $folder = New-Item -Path:$path -Force -ItemType:'' -ErrorAction:Stop;
                } catch {
                    Write-StdErr "Error creating '$path'";
                    Write-LastError -Remove;
                    $result["ShowHelp"] = $true;
                    $folder = $null;
                }
                
                if ($folder -eq $null) { return $null; }
            }
            
            $path = Join-Path -Path:$path -ChildPath:'Modules';
            if (-not (Test-Path -Path:$path -PathType:Container)) {
                if (Test-Path -Path:$ModuleInstallationRootPath -PathType:Leaf) {
                    Write-StdErr "Path '$path' does not point to a folder. Rather, it points to a file.";
                    $result["ShowHelp"] = $true;
                    return $null;
                }
                
                $folder = $null;
                
                try {
                    $folder = New-Item -Path:$path -Force -ItemType:'' -ErrorAction:Stop;
                } catch {
                    Write-StdErr "Error creating '$path'";
                    Write-LastError -Remove;
                    $result["ShowHelp"] = $true;
                    $folder = $null;
                }
                
                if ($folder -eq $null) { return $null; }
            }
        };
    }
    
    if ($result["ModuleName"] -ne $null) {
        $path = Join-Path -Path:(Split-Path -Parent $MyInvocation.MyCommand.Path) -ChildPath:$result["ModuleName"];
        if (Test-Path -Path:$path -PathType:Container) {
            $path = Join-Path -Path:$path -ChildPath:($result["ModuleName"] + '.psm1');
            if (-not (Test-Path -Path:$path -PathType:Leaf)) {
                if (Test-Path -Path:$path -PathType:Container) {
                    Write-StdErr "Path '$path' does not point to a file. Rather, it points to a folder.";
                } else {
                    Write-StdErr "Path '$path' does not exist";
                }
                
                $result["ShowHelp"] = $true;
                $result["ShowExtendedHelp"] = $true;
            }
        } else {
            if (Test-Path -Path:$path -PathType:Leaf) {
                Write-StdErr "Path '$path' does not point to a folder. Rather, it points to a file.";
            } else {
                Write-StdErr "Path '$path' does not exist";
            }
            
            $result["ShowHelp"] = $true;
            $result["ShowExtendedHelp"] = $true;
        }
        
        if ($result["ModuleInstallationRootPath"] -ne $null) {
            $path = Join-Path -Path:$result["ModuleInstallationRootPath"] -ChildPath:$result["ModuleName"];
            if (Test-Path -Path:$path) {
                if (-not $Uninstall) {
                    Write-StdErr "Module is already installed in '$path'.";
                    $result["ShowHelp"] = $true;
                } else {
                    $existingModules = @(Get-Module -ListAvailable -Name LTE);
                    if ($existingModules.Length -gt 0) {
                        Write-StdErr "Module is already installed in '$($existingModules[0].Path)'.";
                        $result["ShowHelp"] = $true;
                    }
                }
            } elseif ($Uninstall) {
                Write-StdErr "Module is not installed in '$path'.";
                $existingModules = @(Get-Module -ListAvailable -Name LTE);
                if ($existingModules.Length -gt 0) {
                    Write-StdErr "Module is installed in '$($existingModules[0].Path)'.";
                    $result["ShowHelp"] = $true;
                }
                $result["ShowHelp"] = $true;
            } else {
                $existingModules = @(Get-Module -ListAvailable -Name LTE);
                if ($existingModules.Length -gt 0) {
                    Write-StdErr "Module is already installed in '$($existingModules[0].Path)'.";
                    $result["ShowHelp"] = $true;
                }
            }
        }
    }
    
    return $result;
}

function Show-Help {
    Write-Host @"
SYNTAX
    Setup.bat -Module <string> [-Install] [-CurrentUser] [-Force] [-ModuleInstallPath <string>] [-Help] [-ExtendedHelp]
        (Alternate: Setup.bat -M <string> [-I] [-C] [-F] [-P <string>] [-?] [-??] )

    Setup.bat -Module <string> [-Install] -SystemWide [-Force] [-ModuleInstallPath] <string> [-Help] [-ExtendedHelp]
        (Alternate: Setup.bat -M <string> [-I] -S [-F] [-P <string>] [-?] [-??] )

    Setup.bat -Module <string> -Uninstall [-CurrentUser] [-ModuleInstallPath <string>] [-Help] [-ExtendedHelp]
        (Alternate: Setup.bat -M <string> -U [-C] [-F] [-P <string>] [-?] [-??] )

    Setup.bat -Module <string> -Uninstall -SystemWide [-ModuleInstallPath <string>] [-Help] [-ExtendedHelp]
        (Alternate: Setup.bat -M <string> -U -S [-F] [-P <string>] [-?] [-??] )


DESCRIPTION
    Installs or uninstalls module by name. Module must be located within a subdirectory of the same name, and must reside in the same subdirectory as the installer script.


PARAMETERS
    -Module <string>
    -M <string>
        Name of module

    -Uninstall
    -U
        Uninstalls module
    
    -Install
    -I
        Installs module
    
    -Force
    -F
        Force uninstall. If this parameter is not provided, and the module is loaded, it will not be uninstalled.
    
    -ModuleInstallPath <string>
    -P <string>
        Custom path to where module is to be installed. This must be the module installation root, and not the actual subdirectory of the module itself.
    
    -Help
    -H
    -?
        Shows help text
    
    -ExtendedHelp
    -X
    -??
        Shows extended help text
    
    -SystemWide
    -S
        Installs module to make it available system-wide
    
    -CurrentUser
    -C
        Installs module to make it available only for the current user
"@;
}

function Show-ExtendedHelp {
    Write-Host @"


Developer notes
    This setup script not only requres that the source folder be in the same directory as the setup script, but that it also contains a file with the same name, and an extension of .psm1.
    If It contains a psd1 file, then that will be copied as well.
"@;
}

function Run-Install {
    Param(
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [string]$ModuleName,
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [boolean]$ModuleInstallationRootPath,
        [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
        [string[]]$RemainingParameters = @()
    )
}

function Run-Uninstall {
    Param(
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [string]$ModuleName,
        [Parameter(Mandatory=$true)]
        [boolean]$Force,
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [boolean]$ModuleInstallationRootPath,
        [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
        [string[]]$RemainingParameters = @()
    )
}

function Run-Setup {
    Param(
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [string]$ModuleName,
        [Parameter(Mandatory=$true)]
        [boolean]$Uninstall,
        [Parameter(Mandatory=$true)]
        [boolean]$Force,
        [Parameter(Mandatory=$true)]
        [AllowNull()]
        [boolean]$ModuleInstallationRootPath,
        [Parameter(Mandatory=$false, ValueFromRemainingArguments=$true)]
        [string[]]$RemainingParameters = @()
    )
    
    if ($Uninstall) {
        Run-Uninstall @PSBoundParameters;
    } else {
        Run-Install @PSBoundParameters
    }
}

$settings = $null;

try {
    $settings = ParseInstallParameters  @PSBoundParameters;

    if (-not $settings["ShowHelp"]) {
        try {
            $settings = ValidateParameters @settings;
        } catch {
            Write-Err 'Unexpected error while validating command line arguments';
            Write-LastError -Remove;
            $settings = $null;
        }
    }
} catch {
    Write-Err 'Invalid command line arguments';
    Write-LastError -Remove;
    $settings = $null;
}

if ($settings -eq $null) { Return }

if ($settings["ShowHelp"])  {
    Show-Help;
    if ($settings["ShowExtendedHelp"])  { Show-ExtendedHelp }
    Return;
}

Run-Setup @settings;
