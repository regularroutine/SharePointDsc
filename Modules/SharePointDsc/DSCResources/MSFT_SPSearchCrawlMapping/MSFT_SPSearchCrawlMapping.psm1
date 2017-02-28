function Get-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Collections.Hashtable])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$ServiceAppName,

		[parameter(Mandatory = $true)]
		[System.String]
		$Url,

		[parameter(Mandatory = $true)]
		[System.String]
		$Target,
		
		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[System.Management.Automation.PSCredential]
		$InstallAccount
	)

	#Write-Verbose "Use this cmdlet to deliver information about command processing."

	#Write-Debug "Use this cmdlet to write debug information while troubleshooting."

	$result = Invoke-SPDSCCommand -Credential $InstallAccount `
								  -Arguments $PSBoundParameters `
								  -ScriptBlock {

		$params = $args[0]
		$searchApp = Get-SPEnterpriseSearchServiceApplication "$($params.ServiceAppName)"
		if($null -eq $searchApp) {
			Write-Verbose -Message "Search Service Application $($params.ServiceAppName) not found"
			$returnVal = @{
				ServiceAppName = ""
				Url = "$($params.Url)"
				Target = "$($params.Target)"
				Ensure = "Absent"
				InstallAccount = $params.InstallAccount
			}
			return $returnVal
		}		
		
		$mappings = $searchApp | Get-SPEnterpriseSearchCrawlMapping
		
		if($null -eq $mappings) {
			Write-Verbose -Message "Search Service Application $($params.ServiceAppName) has no mappings"
			$returnVal = @{
				ServiceAppName = "$($params.ServiceAppName)"
				Url = "$($params.Url)"
				Target = "$($params.Target)"
				Ensure = "Absent"
				InstallAccount = $params.InstallAccount
			}
			return $returnVal
		}
		
		$mapping = $mappings | Where-Object { $_.Source -eq "$($params.Url)" } | Select-Object -First 1
		
		if($null -eq $mapping) {
			Write-Verbose "Search Service Application $($params.ServiceAppName) has no matching mapping"
			$returnVal = @{
				ServiceAppName = "$($params.ServiceAppName)"
				Url = "$($params.Url)"
				Target = "$($params.Target)"
				Ensure = "Absent"
				InstallAccount = $params.InstallAccount
			}
			return $returnVal
		}
		else {
			Write-Verbose "Search Service Application $($params.ServiceAppName) has a matching mapping"
			$returnVal = @{
				ServiceAppName = "$($params.ServiceAppName)"
				Url = "$($mapping.Url)"
				Target = "$($mapping.Target)"
				Ensure = "Present"
				InstallAccount = $params.InstallAccount
			}
			return $returnVal

		}
		
	}

	return $result
	
}


function Set-TargetResource
{
	[CmdletBinding()]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$ServiceAppName,

		[parameter(Mandatory = $true)]
		[System.String]
		$Url,

		[parameter(Mandatory = $true)]
		[System.String]
		$Target,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[System.Management.Automation.PSCredential]
		$InstallAccount
	)

	Write-Verbose -Message "Setting Search Crawl Mapping Rule '$Url'"
	$result = Get-TargetResource @PSBoundParameters

	if($result.Ensure -eq "Absent" -and $Ensure -eq "Present") {
		## Add the Crawl Mapping..
		Write-Verbose "Adding the Crawl Mapping '$Url'"
		Invoke-SPDSCCommand -Credential $InstallAccount `
							-Arguments $PSBoundParameters `
							-ScriptBlock {
			$params = $args[0]

			$searchApp = Get-SPEnterpriseSearchServiceApplication "$($params.ServiceAppName)"
			if($null -eq $searchApp) {
				Write-Verbose -Message "Search Service Application $($params.ServiceAppName) not found"
				throw ("When ServiceAppName does not reference a Search Application which exists, we cannot add mappings")
			}
			else {
				New-SPEnterpriseSearchCrawlMapping -SearchApplication $searchApp -Url $params.Url -Target $params.Target						
			}
		}
	}
	if($result.Ensure -eq "Present" -and $Ensure -eq "Present") {
		##Update the Crawl Rule..
		Write-Verbose "Updating the Crawl Mapping '$Url'"
		Invoke-SPDSCCommand -Credential $InstallAccount `
							-Arguments $PSBoundParameters `
							-ScriptBlock {
			$params = $args[0]		

			$searchApp = Get-SPEnterpriseSearchServiceApplication "$($params.ServiceAppName)"
			$mappings = $searchApp | Get-SPEnterpriseSearchCrawlMapping
			$mapping = $mappings | Where-Object { $_.Source -eq "$($params.Url)" } | Select-Object -First 1
			$mapping | Remove-SPEnterpriseSearchCrawlMapping

			New-SPEnterpriseSearchCrawlMapping -SearchApplication $searchApp -Url $params.Url -Target $params.Target							
		}
	}
	if($result.Ensure -eq "Present" -and $Ensure -eq "Absent") {
		## Remove the Crawl Mapping..
		Write-Verbose "Removing the Crawl Mapping '$Url'"
		Invoke-SPDSCCommand -Credential $InstallAccount `
							-Arguments $PSBoundParameters `
							-ScriptBlock {
			$params = $args[0]
			
			$searchapp = Get-SPEnterpriseSearchServiceApplication "$($params.ServiceAppName)"
			$mappings = $searchApp | Get-SPEnterpriseSearchCrawlMapping
			$mapping = $mappings | Where-Object { $_.Source -eq "$($params.Url)" } | Select-Object -First 1
			$mapping | Remove-SPEnterpriseSearchCrawlMapping					
		}
	}
}


function Test-TargetResource
{
	[CmdletBinding()]
	[OutputType([System.Boolean])]
	param
	(
		[parameter(Mandatory = $true)]
		[System.String]
		$ServiceAppName,

		[parameter(Mandatory = $true)]
		[System.String]
		$Url,

		[parameter(Mandatory = $true)]
		[System.String]
		$Target,

		[ValidateSet("Present","Absent")]
		[System.String]
		$Ensure,

		[System.Management.Automation.PSCredential]
		$InstallAccount
	)

	$PSBoundParameters.Ensure = $Ensure

	$CurrentValues = Get-TargetResource @PSBoundParameters

	if($Ensure -eq "Present") {
		return Test-SPDscParameterState -CurrentValues $CurrentValues `
										-DesiredValues $PSBoundParameters `
									    -ValuesToCheck @("ServiceAppName","Url","Target","Ensure")
	}
	else {
		return Test-SPDscParameterState -CurrentValues $CurrentValues `
										-DesiredValues $PSBoundParameters `
									    -ValuesToCheck @("Ensure")
	}
}


Export-ModuleMember -Function *-TargetResource

