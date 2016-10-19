[CmdletBinding()]
param(
    [string] $SharePointCmdletModule = (Join-Path $PSScriptRoot "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" -Resolve)
)

$ErrorActionPreference = 'stop'
Set-StrictMode -Version latest

$RepoRoot = (Resolve-Path $PSScriptRoot\..\..\..).Path
$Global:CurrentSharePointStubModule = $SharePointCmdletModule 

$ModuleName = "MSFT_SPUsageApplication"
Import-Module (Join-Path $RepoRoot "Modules\SharePointDsc\DSCResources\$ModuleName\$ModuleName.psm1") -Force

Describe "SPUsageApplication - SharePoint Build $((Get-Item $SharePointCmdletModule).Directory.BaseName)" {
    InModuleScope $ModuleName {
        $testParams = @{
            Name = "Usage Service App"
            UsageLogCutTime = 60
            UsageLogLocation = "L:\UsageLogs"
            UsageLogMaxFileSizeKB = 1024
            UsageLogMaxSpaceGB = 10
            DatabaseName = "SP_Usage"
            DatabaseServer = "sql.test.domain"
            FailoverDatabaseServer = "anothersql.test.domain"
            Ensure = "Present"
        }
        $getTypeFullName = "Microsoft.SharePoint.Administration.SPUsageApplication"
        $getTypeFullNameProxy = "Microsoft.SharePoint.Administration.SPUsageApplicationProxy"
        
        Import-Module (Join-Path ((Resolve-Path $PSScriptRoot\..\..\..).Path) "Modules\SharePointDsc")
        
        Mock Invoke-SPDSCCommand { 
            return Invoke-Command -ScriptBlock $ScriptBlock -ArgumentList $Arguments -NoNewScope
        }
        
        Remove-Module -Name "Microsoft.SharePoint.PowerShell" -Force -ErrorAction SilentlyContinue
        Import-Module $Global:CurrentSharePointStubModule -WarningAction SilentlyContinue 
        
        Mock New-SPUsageApplication { }
        Mock Set-SPUsageService { }
        Mock Get-SPUsageService { return @{
            UsageLogCutTime = $testParams.UsageLogCutTime
            UsageLogDir = $testParams.UsageLogLocation
            UsageLogMaxFileSize = ($testParams.UsageLogMaxFileSizeKB * 1024)
            UsageLogMaxSpaceGB = $testParams.UsageLogMaxSpaceGB
        }}
        Mock Remove-SPServiceApplication
        Mock Get-SPServiceApplicationProxy {
            $spServiceAppProxy = [pscustomobject]@{
                    Status = "Online"
                }
                $spServiceAppProxy | Add-Member ScriptMethod Provision {} -PassThru
                $spServiceAppProxy | Add-Member ScriptMethod GetType { 
                    return @{ FullName = $getTypeFullNameProxy } 
                } -PassThru -Force
                return $spServiceAppProxy
        }

        Context "When no service applications exist in the current farm" {

            Mock Get-SPServiceApplication { return $null }

            It "returns null from the Get method" {
                (Get-TargetResource @testParams).Ensure | Should Be "Absent"  
            }

            It "returns false when the Test method is called" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "creates a new service application in the set method" {
                Set-TargetResource @testParams
                Assert-MockCalled New-SPUsageApplication
            }

            It "creates a new service application with custom database credentials" {
                $testParams.Add("DatabaseCredentials", (New-Object System.Management.Automation.PSCredential ("username", (ConvertTo-SecureString "password" -AsPlainText -Force))))
                Set-TargetResource @testParams
                Assert-MockCalled New-SPUsageApplication
            }
        }

        Context "When service applications exist in the current farm but not the specific usage service app" {
            Mock Get-SPServiceApplication {
                $spServiceApp = [pscustomobject]@{
                    DisplayName = $testParams.Name
                }
                $spServiceApp | Add-Member ScriptMethod GetType { 
                    return @{ FullName = "Microsoft.Office.UnKnownWebServiceApplication" } 
                } -PassThru -Force
                return $spServiceApp
            }

            It "returns absent from the Get method" {
                (Get-TargetResource @testParams).Ensure | Should Be "Absent"  
            }

            It "returns false when the Test method is called" {
                Test-TargetResource @testParams | Should Be $false
            }
        }

        Context "When a service application exists and is configured correctly" {
            Mock Get-SPServiceApplication {
                $spServiceApp = [pscustomobject]@{
                    DisplayName = $testParams.Name
                    UsageDatabase = @{
                        Name = $testParams.DatabaseName
                        Server = @{ Name = $testParams.DatabaseServer }
                    }
                }
                $spServiceApp = $spServiceApp | Add-Member ScriptMethod GetType { 
                    return @{ FullName = $getTypeFullName } 
                } -PassThru -Force
                return $spServiceApp
            }

            It "returns values from the get method" {
                (Get-TargetResource @testParams).Ensure | Should Be "Present"  
            }

            It "returns true when the Test method is called" {
                Test-TargetResource @testParams | Should Be $true
            }
        }

        Context "When a service application exists and log path are not configured correctly" {
            Mock Get-SPServiceApplication {
                $spServiceApp = [pscustomobject]@{
                    DisplayName = $testParams.Name
                    UsageDatabase = @{
                        Name = $testParams.DatabaseName
                        Server = @{ Name = $testParams.DatabaseServer }
                    }
                }
                $spServiceApp = $spServiceApp | Add-Member ScriptMethod GetType { 
                    return @{ FullName = $getTypeFullName } 
                } -PassThru -Force
                return $spServiceApp
            }
            Mock Get-SPUsageService { return @{
                UsageLogCutTime = $testParams.UsageLogCutTime
                UsageLogDir = "C:\Wrong\Location"
                UsageLogMaxFileSize = ($testParams.UsageLogMaxFileSizeKB * 1024)
                UsageLogMaxSpaceGB = $testParams.UsageLogMaxSpaceGB
            }}

            It "returns false when the Test method is called" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "calls the update service app cmdlet from the set method" {
                Set-TargetResource @testParams

                Assert-MockCalled Set-SPUsageService
            }
        }

        Context "When a service application exists and log size is not configured correctly" {
            Mock Get-SPServiceApplication {
                $spServiceApp = [pscustomobject]@{
                    DisplayName = $testParams.Name
                    UsageDatabase = @{
                        Name = $testParams.DatabaseName
                        Server = @{ Name = $testParams.DatabaseServer }
                    }
                }
                $spServiceApp = $spServiceApp | Add-Member ScriptMethod GetType { 
                    return @{ FullName = $getTypeFullName } 
                } -PassThru -Force
                return $spServiceApp
            }
            Mock Get-SPUsageService { return @{
                UsageLogCutTime = $testParams.UsageLogCutTime
                UsageLogDir = $testParams.UsageLogLocation
                UsageLogMaxFileSize = ($testParams.UsageLogMaxFileSizeKB * 1024)
                UsageLogMaxSpaceGB = 1
            }}

            It "returns false when the Test method is called" {
                Test-TargetResource @testParams | Should Be $false
            }

            It "calls the update service app cmdlet from the set method" {
                Set-TargetResource @testParams

                Assert-MockCalled Set-SPUsageService
            }
        }
        
        $testParams = @{
            Name = "Test App"
            Ensure = "Absent"
        }
        
        Context "When the service app exists but it shouldn't" {
            Mock Get-SPServiceApplication {
                $spServiceApp = [pscustomobject]@{
                    DisplayName = $testParams.Name
                    UsageDatabase = @{
                        Name = $testParams.DatabaseName
                        Server = @{ Name = $testParams.DatabaseServer }
                    }
                }
                $spServiceApp = $spServiceApp | Add-Member ScriptMethod GetType { 
                    return @{ FullName = $getTypeFullName } 
                } -PassThru -Force
                return $spServiceApp
            }
            
            It "returns present from the Get method" {
                (Get-TargetResource @testParams).Ensure | Should Be "Present" 
            }
            
            It "should return false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }
            
            It "should remove the service application in the set method" {
                Set-TargetResource @testParams
                Assert-MockCalled Remove-SPServiceApplication
            }
        }
        
        Context "When the service app doesn't exist and shouldn't" {
            Mock Get-SPServiceApplication { return $null }
            
            It "returns absent from the Get method" {
                (Get-TargetResource @testParams).Ensure | Should Be "Absent" 
            }
            
            It "should return false from the test method" {
                Test-TargetResource @testParams | Should Be $true
            }
        }
        
        $testParams = @{
            Name = "Test App"
            Ensure = "Present"
        }
        
        Context "The proxy for the service app is offline when it should be running" {
            Mock Get-SPServiceApplication {
                $spServiceApp = [pscustomobject]@{
                    DisplayName = $testParams.Name
                    UsageDatabase = @{
                        Name = $testParams.DatabaseName
                        Server = @{ Name = $testParams.DatabaseServer }
                    }
                }
                $spServiceApp = $spServiceApp | Add-Member ScriptMethod GetType { 
                    return @{ FullName = $getTypeFullName } 
                } -PassThru -Force
                return $spServiceApp
            }
            Mock Get-SPServiceApplicationProxy {
            $spServiceAppProxy = [pscustomobject]@{
                    Status = "Disabled"
                }
                $spServiceAppProxy | Add-Member ScriptMethod Provision {
                    $Global:SPDSCUSageAppProxyStarted = $true
                } -PassThru
                $spServiceAppProxy | Add-Member ScriptMethod GetType { 
                    return @{ FullName = $getTypeFullNameProxy } 
                } -PassThru -Force
                return $spServiceAppProxy
            }
  
            $Global:SPDSCUSageAppProxyStarted = $false
            
            It "should return absent from the get method" {
                (Get-TargetResource @testParams).Ensure | Should Be "Absent" 
            }
            
            It "should return false from the test method" {
                Test-TargetResource @testParams | Should Be $false
            }
            
            It "should start the proxy in the set method" {
                Set-TargetResource @testParams
                $Global:SPDSCUSageAppProxyStarted | Should Be $true
            }
        }
    }    
}
