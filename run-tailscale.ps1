$envFile = Join-Path $PSScriptRoot '.env'

if (-not (Test-Path -LiteralPath $envFile)) {
	[Console]::Error.WriteLine('.env not found - copy .env.example to .env first')
	exit 1
}

if (-not (Select-String -LiteralPath $envFile -Pattern '^TAILSCALE_AUTHKEY=..+' -Quiet)) {
	[Console]::Error.WriteLine('TAILSCALE_AUTHKEY is missing from .env - see .env.example')
	exit 1
}

# The `tailscale` profile is the feature flag for the tailnet-only sidecar.
$code = 0
Push-Location $PSScriptRoot
try {
	docker compose `
		-f docker-compose.yml `
		-f docker-compose.local.yml `
		-f docker-compose.tailscale.yml `
		--profile tailscale `
		up --build
	$code = $LASTEXITCODE
}
finally {
	Pop-Location
}

exit $code