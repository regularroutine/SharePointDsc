[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute("PSAvoidUsingConvertToSecureStringWithPlainText", "")]
param
(
    [Parameter()]
    [string]
    $SharePointCmdletModule = (Join-Path -Path $PSScriptRoot `
            -ChildPath "..\Stubs\SharePoint\15.0.4805.1000\Microsoft.SharePoint.PowerShell.psm1" `
            -Resolve)
)

$script:DSCModuleName = 'SharePointDsc'
$script:DSCResourceName = 'SPSecureStoreServiceApp'
$script:DSCResourceFullName = 'MSFT_' + $script:DSCResourceName

function Invoke-TestSetup
{
    try
    {
        Import-Module -Name DscResource.Test -Force

        Import-Module -Name (Join-Path -Path $PSScriptRoot `
                -ChildPath "..\UnitTestHelper.psm1" `
                -Resolve)

        $Global:SPDscHelper = New-SPDscUnitTestHelper -SharePointStubModule $SharePointCmdletModule `
            -DscResource $script:DSCResourceName
    }
    catch [System.IO.FileNotFoundException]
    {
        throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
    }

    $script:testEnvironment = Initialize-TestEnvironment `
        -DSCModuleName $script:DSCModuleName `
        -DSCResourceName $script:DSCResourceFullName `
        -ResourceType 'Mof' `
        -TestType 'Unit'
}

function Invoke-TestCleanup
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}

Invoke-TestSetup

try
{
    Describe -Name $Global:SPDscHelper.DescribeHeader -Fixture {
        InModuleScope -ModuleName $Global:SPDscHelper.ModuleName -ScriptBlock {
            Invoke-Command -ScriptBlock $Global:SPDscHelper.InitializeScript -NoNewScope

            # Initialize tests
            $getTypeFullName = "Microsoft.Office.SecureStoreService.Server.SecureStoreServiceApplication"
            $mockPassword = ConvertTo-SecureString -String "passwprd" -AsPlainText -Force
            $mockCredential = New-Object -TypeName System.Management.Automation.PSCredential `
                -ArgumentList @("SqlUser", $mockPassword)

            # Mocks for all contexts
            Mock -CommandName Remove-SPServiceApplication -MockWith { }
            Mock -CommandName New-SPSecureStoreServiceApplication -MockWith { }
            Mock -CommandName New-SPSecureStoreServiceApplicationProxy -MockWith { }
            Mock -CommandName Set-SPSecureStoreServiceApplication -MockWith { }

            # Test contexts
            Context -Name "When no service application exists in the current farm" -Fixture {
                $testParams = @{
                    Name            = "Secure Store Service Application"
                    ApplicationPool = "SharePoint Search Services"
                    AuditingEnabled = $false
                    Ensure          = "Present"
                }

                Mock -CommandName Get-SPServiceApplication -MockWith {
                    return $null
                }

                It "Should return absent from the Get method" {
                    (Get-TargetResource @testParams).Ensure | Should Be "Absent"
                }

                It "Should return false when the Test method is called" {
                    Test-TargetResource @testParams | Should Be $false
                }

                It "Should create a new service application in the set method" {
                    Set-TargetResource @testParams
                    Assert-MockCalled New-SPSecureStoreServiceApplication
                }

                $testParams.Add("DatabaseName", "SP_SecureStore")
                It "Should create a new service application in the set method where parameters beyond the minimum required set" {
                    Set-TargetResource @testParams
                    Assert-MockCalled New-SPSecureStoreServiceApplication
                }
            }

            Context -Name "When service applications exist in the current farm but the specific search app does not" -Fixture {
                $testParams = @{
                    Name            = "Secure Store Service Application"
                    ApplicationPool = "SharePoint Search Services"
                    AuditingEnabled = $false
                    Ensure          = "Present"
                }

                Mock -CommandName Get-SPServiceApplication -MockWith {
                    $spServiceApp = [PSCustomObject]@{
                        DisplayName = $testParams.Name
                    }
                    $spServiceApp | Add-Member -MemberType ScriptMethod `
                        -Name GetType `
                        -Value {
                        return @{
                            FullName = "Microsoft.Office.UnKnownWebServiceApplication"
                        }
                    } -PassThru -Force
                    return $spServiceApp
                }

                It "Should return absent from the Get method" {
                    (Get-TargetResource @testParams).Ensure | Should Be "Absent"
                }

                It "Should return false when the Test method is called" {
                    Test-TargetResource @testParams | Should Be $false
                }
            }

            Context -Name "When a service application exists and is configured correctly" -Fixture {
                $testParams = @{
                    Name            = "Secure Store Service Application"
                    ApplicationPool = "SharePoint Search Services"
                    AuditingEnabled = $false
                    Ensure          = "Present"
                }

                Mock -CommandName Get-SPServiceApplication -MockWith {
                    $spServiceApp = [PSCustomObject]@{
                        TypeName        = "Secure Store Service Application"
                        DisplayName     = $testParams.Name
                        ApplicationPool = @{
                            Name = $testParams.ApplicationPool
                        }
                    }
                    $spServiceApp = $spServiceApp | Add-Member -MemberType ScriptMethod -Name GetType -Value {
                        New-Object -TypeName "Object" |
                        Add-Member -MemberType NoteProperty `
                            -Name FullName `
                            -Value $getTypeFullName `
                            -PassThru |
                        Add-Member -MemberType ScriptMethod `
                            -Name GetProperties `
                            -Value {
                            param($x)
                            return @(
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "Database" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return (@{
                                                FullName             = $getTypeFullName
                                                Name                 = "Database"
                                                NormalizedDataSource = "DBServer"
                                                Server               = @{
                                                    Name = "DBServer"
                                                }
                                                FailoverServer       = @{
                                                    Name = "DBServer_Failover"
                                                }
                                            })
                                    } -PassThru
                                ),
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "AuditEnabled" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return $params.AuditEnabled
                                    } -PassThru
                                )
                            )
                        } -PassThru
                    } -PassThru -Force

                    return $spServiceApp
                }

                It "Should return present from the get method" {
                    (Get-TargetResource @testParams).Ensure | Should Be "Present"
                }

                It "Should return true when the Test method is called" {
                    Test-TargetResource @testParams | Should Be $true
                }
            }

            Context -Name "When a service application exists and the app pool is not configured correctly" -Fixture {
                $testParams = @{
                    Name            = "Secure Store Service Application"
                    ApplicationPool = "SharePoint Search Services"
                    AuditingEnabled = $false
                    Ensure          = "Present"
                }

                Mock -CommandName Get-SPServiceApplication -MockWith {
                    $spServiceApp = [PSCustomObject]@{
                        TypeName        = "Secure Store Service Application"
                        DisplayName     = $testParams.Name
                        ApplicationPool = @{
                            Name = "Wrong App Pool Name"
                        }
                    }
                    $spServiceApp = $spServiceApp | Add-Member -MemberType ScriptMethod -Name GetType -Value {
                        New-Object -TypeName "Object" |
                        Add-Member -MemberType NoteProperty `
                            -Name FullName `
                            -Value $getTypeFullName `
                            -PassThru |
                        Add-Member -MemberType ScriptMethod `
                            -Name GetProperties `
                            -Value {
                            param($x)
                            return @(
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "Database" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return (@{
                                                FullName             = $getTypeFullName
                                                Name                 = "Database"
                                                NormalizedDataSource = "DBServer"
                                                Server               = @{
                                                    Name = "DBServer"
                                                }
                                                FailoverServer       = @{
                                                    Name = "DBServer_Failover"
                                                }
                                            })
                                    } -PassThru
                                ),
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "AuditEnabled" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return $params.AuditEnabled
                                    } -PassThru
                                )
                            )
                        } -PassThru
                    } -PassThru -Force

                    return $spServiceApp
                }

                Mock -CommandName Get-SPServiceApplicationPool -MockWith {
                    return @{
                        Name = $testParams.ApplicationPool
                    }
                }

                It "Should return false when the Test method is called" {
                    Test-TargetResource @testParams | Should Be $false
                }

                It "Should call the update service app cmdlet from the set method" {
                    Set-TargetResource @testParams

                    Assert-MockCalled Get-SPServiceApplicationPool
                    Assert-MockCalled Set-SPSecureStoreServiceApplication
                }
            }

            Context -Name "When specific windows credentials are to be used for the database" -Fixture {
                $testParams = @{
                    Name                       = "Secure Store Service Application"
                    ApplicationPool            = "SharePoint Search Services"
                    AuditingEnabled            = $false
                    DatabaseName               = "SP_ManagedMetadata"
                    DatabaseCredentials        = $mockCredential
                    DatabaseAuthenticationType = "Windows"
                    Ensure                     = "Present"
                }

                Mock -CommandName Get-SPServiceApplication -MockWith {
                    return $null
                }

                It "allows valid Windows credentials can be passed" {
                    Set-TargetResource @testParams
                    Assert-MockCalled New-SPSecureStoreServiceApplication
                }

                It "Should throw an exception if database authentication type is not specified" {
                    $testParams.Remove("DatabaseAuthenticationType")
                    { Set-TargetResource @testParams } | Should Throw
                }

                It "Should throw an exception if the credentials aren't provided and the authentication type is set" {
                    $testParams.Add("DatabaseAuthenticationType", "Windows")
                    $testParams.Remove("DatabaseCredentials")
                    { Set-TargetResource @testParams } | Should Throw
                }
            }

            Context -Name "When specific SQL credentials are to be used for the database" -Fixture {
                $testParams = @{
                    Name                       = "Secure Store Service Application"
                    ApplicationPool            = "SharePoint Search Services"
                    AuditingEnabled            = $false
                    DatabaseName               = "SP_ManagedMetadata"
                    DatabaseCredentials        = $mockCredential
                    DatabaseAuthenticationType = "SQL"
                    Ensure                     = "Present"
                }

                Mock -CommandName Get-SPServiceApplication -MockWith { return $null }

                It "allows valid SQL credentials can be passed" {
                    Set-TargetResource @testParams
                    Assert-MockCalled New-SPSecureStoreServiceApplication
                }

                It "Should throw an exception if database authentication type is not specified" {
                    $testParams.Remove("DatabaseAuthenticationType")
                    { Set-TargetResource @testParams } | Should Throw
                }

                It "Should throw an exception if the credentials aren't provided and the authentication type is set" {
                    $testParams.Add("DatabaseAuthenticationType", "Windows")
                    $testParams.Remove("DatabaseCredentials")
                    { Set-TargetResource @testParams } | Should Throw
                }
            }

            Context -Name "When the service app exists but it shouldn't" -Fixture {
                $testParams = @{
                    Name            = "Secure Store Service Application"
                    ApplicationPool = "-"
                    AuditingEnabled = $false
                    Ensure          = "Absent"
                }

                Mock -CommandName Get-SPServiceApplication -MockWith {
                    $spServiceApp = [PSCustomObject]@{
                        TypeName        = "Secure Store Service Application"
                        DisplayName     = $testParams.Name
                        ApplicationPool = @{
                            Name = "Wrong App Pool Name"
                        }
                    }
                    $spServiceApp = $spServiceApp | Add-Member -MemberType ScriptMethod -Name GetType -Value {
                        New-Object -TypeName "Object" |
                        Add-Member -MemberType NoteProperty `
                            -Name FullName `
                            -Value $getTypeFullName `
                            -PassThru |
                        Add-Member -MemberType ScriptMethod `
                            -Name GetProperties `
                            -Value {
                            param($x)
                            return @(
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "Database" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return (@{
                                                FullName             = $getTypeFullName
                                                Name                 = "Database"
                                                NormalizedDataSource = "DBServer"
                                                Server               = @{
                                                    Name = "DBServer"
                                                }
                                                FailoverServer       = @{
                                                    Name = "DBServer_Failover"
                                                }
                                            })
                                    } -PassThru
                                ),
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "AuditEnabled" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return $params.AuditEnabled
                                    } -PassThru
                                )
                            )
                        } -PassThru
                    } -PassThru -Force

                    return $spServiceApp
                }

                It "Should return present from the Get method" {
                    (Get-TargetResource @testParams).Ensure | Should Be "Present"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should Be $false
                }

                It "Should remove the service application in the set method" {
                    Set-TargetResource @testParams
                    Assert-MockCalled Remove-SPServiceApplication
                }
            }

            Context -Name "When the database name does not match the actual name" -Fixture {
                $testParams = @{
                    Name            = "Secure Store Service Application"
                    ApplicationPool = "Service App Pool"
                    AuditingEnabled = $false
                    DatabaseName    = "SecureStoreDB"
                    Ensure          = "Present"
                }

                Mock -CommandName Get-SPServiceApplication -MockWith {
                    $spServiceApp = [PSCustomObject]@{
                        TypeName        = "Secure Store Service Application"
                        DisplayName     = $testParams.Name
                        ApplicationPool = @{
                            Name = $testParams.ApplicationPool
                        }
                    }
                    $spServiceApp = $spServiceApp | Add-Member -MemberType ScriptMethod -Name GetType -Value {
                        New-Object -TypeName "Object" |
                        Add-Member -MemberType NoteProperty `
                            -Name FullName `
                            -Value $getTypeFullName `
                            -PassThru |
                        Add-Member -MemberType ScriptMethod `
                            -Name GetProperties `
                            -Value {
                            param($x)
                            return @(
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "Database" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return (@{
                                                FullName             = $getTypeFullName
                                                Name                 = "Wrong Database"
                                                NormalizedDataSource = "DBServer"
                                                Server               = @{
                                                    Name = "DBServer"
                                                }
                                                FailoverServer       = @{
                                                    Name = "DBServer_Failover"
                                                }
                                            })
                                    } -PassThru
                                ),
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "AuditEnabled" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return $params.AuditEnabled
                                    } -PassThru
                                )
                            )
                        } -PassThru
                    } -PassThru -Force

                    return $spServiceApp
                }

                It "Should return present from the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should Be "Present"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should Be $false
                }

                It "Should throw exception in the set method" {
                    { Set-TargetResource @testParams } | Should Throw ("Specified database name does not match " + `
                            "the actual database name. This resource " + `
                            "cannot rename the database.")
                }
            }

            Context -Name "When the database server does not match the actual server" -Fixture {
                $testParams = @{
                    Name            = "Secure Store Service Application"
                    ApplicationPool = "Service App Pool"
                    AuditingEnabled = $false
                    DatabaseName    = "SecureStoreDB"
                    DatabaseServer  = "SQL_Instance"
                    Ensure          = "Present"
                }

                Mock -CommandName Get-SPServiceApplication -MockWith {
                    $spServiceApp = [PSCustomObject]@{
                        TypeName        = "Secure Store Service Application"
                        DisplayName     = $testParams.Name
                        ApplicationPool = @{
                            Name = $testParams.ApplicationPool
                        }
                    }
                    $spServiceApp = $spServiceApp | Add-Member -MemberType ScriptMethod -Name GetType -Value {
                        New-Object -TypeName "Object" |
                        Add-Member -MemberType NoteProperty `
                            -Name FullName `
                            -Value $getTypeFullName `
                            -PassThru |
                        Add-Member -MemberType ScriptMethod `
                            -Name GetProperties `
                            -Value {
                            param($x)
                            return @(
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "Database" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return (@{
                                                FullName             = $getTypeFullName
                                                Name                 = "SecureStoreDB"
                                                NormalizedDataSource = "Wrong DBServer"
                                                Server               = @{
                                                    Name = "Wrong DBServer"
                                                }
                                                FailoverServer       = @{
                                                    Name = "DBServer_Failover"
                                                }
                                            })
                                    } -PassThru
                                ),
                                (New-Object -TypeName "Object" |
                                    Add-Member -MemberType NoteProperty `
                                        -Name Name `
                                        -Value "AuditEnabled" `
                                        -PassThru |
                                    Add-Member -MemberType ScriptMethod `
                                        -Name GetValue `
                                        -Value {
                                        param($x)
                                        return $params.AuditEnabled
                                    } -PassThru
                                )
                            )
                        } -PassThru
                    } -PassThru -Force

                    return $spServiceApp
                }

                It "Should return present from the Get method" {
                    $result = Get-TargetResource @testParams
                    $result.Ensure | Should Be "Present"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should Be $false
                }

                It "Should throw exception in the set method" {
                    { Set-TargetResource @testParams } | Should Throw ("Specified database server does " + `
                            "not match the actual database server. " + `
                            "This resource cannot move the database " + `
                            "to a different SQL instance.")
                }
            }

            Context -Name "When the service app doesn't exist and shouldn't" -Fixture {
                $testParams = @{
                    Name            = "Secure Store Service Application"
                    ApplicationPool = "-"
                    AuditingEnabled = $false
                    Ensure          = "Absent"
                }

                Mock -CommandName Get-SPServiceApplication -MockWith {
                    return $null
                }

                It "Should return absent from the Get method" {
                    (Get-TargetResource @testParams).Ensure | Should Be "Absent"
                }

                It "Should return false from the test method" {
                    Test-TargetResource @testParams | Should Be $true
                }
            }
        }
    }
}
finally
{
    Invoke-TestCleanup
}
