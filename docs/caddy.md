# Caddy security headers

Reverse proxy in front of your apps: add a reusable snippet to the `Caddyfile`.

```caddyfile
{
	# Admin API only on loopback (this is the default; keep it explicit).
	admin localhost:2019
}

(secure_headers) {
	header {
		Strict-Transport-Security "max-age=31536000; includeSubDomains"
		X-Content-Type-Options "nosniff"
		Referrer-Policy "strict-origin-when-cross-origin"
		X-Frame-Options "SAMEORIGIN"
		-Server
		-X-Powered-By
	}
}

app.example.com {
	import secure_headers
	reverse_proxy 127.0.0.1:8080
}
```

- Add `preload` to HSTS only when every subdomain is HTTPS-only for good.
- Upstreams should listen on `127.0.0.1`, so the only public ports are Caddy's 80/443 (see `FW_TCP_PORTS`).
- HTTP/3 needs `udp 443`, which is open by default in `config.example.env`.
- Check: `curl -sI https://app.example.com | grep -iE 'strict|server'`.
