$code = 0

Push-Location $PSScriptRoot
try {
	# --remove-orphans drops the tailscale sidecar when the tailnet variant ran before.
	docker compose `
		-f docker-compose.yml `
		-f docker-compose.local.yml `
		up --build --remove-orphans
	$code = $LASTEXITCODE
}
finally {
	Pop-Location
}

exit $code