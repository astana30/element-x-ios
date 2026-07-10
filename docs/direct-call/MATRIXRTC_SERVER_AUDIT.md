# SalemX MatrixRTC Server Audit

Audit date: 2026-07-10

Local baseline:
- Branch: `salemx-2.47a-controlled-media-credentials-boundary`
- Commit: `b654c298c67fae3f1659c1d552320cfc0bccb7e9`
- Scope: Stage 1A read-only MatrixRTC server audit.

Safety:
- Remote access used the existing `salemx-staging-codex` SSH alias.
- The exact read-only SSH proof returned `salemx_read_only_access_ok`.
- No server files, services, containers, firewall rules, Redis data, database data, Matrix events, LiveKit rooms, APNs, iOS apps, media, dependencies, signing, or runtime code were changed.
- No raw tokens, user IDs, device IDs, room IDs, call IDs, Redis credentials, LiveKit secrets, APNs tokens, PushKit tokens, private keys, auth headers, or raw logs are recorded here.

## Deployment Topology

Observed topology:
- Synapse: `matrix-synapse.service`, systemd, active/running, version `1.150.0`.
- Extra Synapse service: `matrix-synapse-mertis.service`, systemd, observed in activating/auto-restart state. It was not remediated.
- nginx: `nginx.service`, systemd, active/running, version `nginx/1.18.0`.
- SalemX call-service: `salemx-call-service.service`, systemd, active/running, bound to localhost port `8091`.
- MatrixRTC Auth Service: `lk-jwt-service` process present, not visible as a systemd service to the unprivileged audit user.
- LiveKit SFU: `livekit-server` process present, not visible as a systemd service to the unprivileged audit user.
- Redis: `redis-server` process present, not visible as a systemd service to the unprivileged audit user.
- Docker API: present but inaccessible to the audit user, so container images, immutable digests, and pinning could not be proven.

Public names:
- Matrix server name: `mertis.kz`
- Matrix public base URL: `https://matrix.mertis.kz/`
- MatrixRTC focus URL advertised by `.well-known`: `https://matrix.mertis.kz/livekit/jwt`
- LiveKit public host: `rtc.mertis.kz`

## Component Versions And Pinning

| Component | Version known | Version / bucket | Pinning / digest |
| --- | --- | --- | --- |
| Synapse | true | `1.150.0` | host package/venv pinning not proven |
| nginx | true | `nginx/1.18.0` | system package pinning not proven |
| SalemX call-service | unknown | active service | deployment revision not proven in read-only audit |
| MatrixRTC Auth Service | false | process present; binary/version inaccessible | UNKNOWN |
| LiveKit SFU | false | process present; binary/config inaccessible | UNKNOWN |
| Redis | false | process present; binary inaccessible | UNKNOWN |

## Synapse MatrixRTC Prerequisites

| Requirement | Result | Evidence bucket |
| --- | --- | --- |
| Synapse version known | PASS | `1.150.0` |
| Matrix server name known | PASS | `mertis.kz` |
| `experimental_features.msc3266_enabled` | PASS | `true` |
| `experimental_features.msc4222_enabled` | PASS | `true` |
| `max_event_delay_duration` | PASS | `24h` |
| `rc_message.per_second` | UNKNOWN | value not proven |
| `rc_message.burst_count` | UNKNOWN | value not proven |
| `rc_delayed_event_mgmt.per_second` | UNKNOWN | value not proven |
| `rc_delayed_event_mgmt.burst_count` | UNKNOWN | value not proven |
| OpenID or federation listener | PASS | federation listener present; OpenID listener absent |
| Federation closed | PASS | federation whitelist present and empty |
| Public client versions endpoint | PASS | HTTP `200`, JSON |
| MatrixRTC unstable feature advertisement | UNKNOWN | relevant unstable flags not proven in `/versions` |
| Delayed-event API appears enabled | UNKNOWN | unauthenticated non-mutating probes were inconclusive |

## Well-Known

| Requirement | Result | Evidence bucket |
| --- | --- | --- |
| HTTP status | PASS | `200` |
| Content type JSON | PASS | `application/json` |
| CORS for Matrix clients | PASS | header present |
| Valid JSON | PASS | true |
| Homeserver base URL | PASS | `https://matrix.mertis.kz` |
| Auth issuer presence | PASS | present_redacted |
| MatrixRTC foci present | PASS | true |
| MatrixRTC foci count | PASS | `1` |
| Focus type | PASS | `livekit` |
| Focus URL reaches deployed auth service | FAIL_CRITICAL | `.well-known` advertises `/livekit/jwt`, but nginx exposes auth-service routes as `/sfu/get`, `/get_token`, and `/healthz`; `/livekit/jwt` returned `404` |
| Duplicate/conflicting MatrixRTC focus keys | PASS | none observed in parsed client well-known |

## Auth Service

| Requirement | Result | Evidence bucket |
| --- | --- | --- |
| Service identified | PASS | `lk-jwt-service` process present |
| Version known | UNKNOWN | binary/version inaccessible to audit user |
| Image pinned / immutable digest | UNKNOWN | Docker API inaccessible |
| Health endpoint | PASS | `/healthz` returned `200` |
| Internal bind direct public exposure | UNKNOWN | process env and container bind details inaccessible; nginx routes only prove localhost proxy to `8090` |
| `LIVEKIT_URL` matches public target | UNKNOWN | process environment inaccessible |
| `LIVEKIT_FULL_ACCESS_HOMESERVERS` present/restricted | UNKNOWN | process environment inaccessible |
| Wildcard homeserver disabled | UNKNOWN | process environment inaccessible |
| LiveKit key/secret present | UNKNOWN | process environment inaccessible |
| Redis configured | UNKNOWN | process environment inaccessible |
| Sanity check interval non-zero | UNKNOWN | process environment inaccessible |
| TLS verification bypass disabled | UNKNOWN | process environment inaccessible |
| Webhook receiver route | UNKNOWN | LiveKit config inaccessible; auth process route not fully enumerable |
| Unauthenticated token issuance | PASS | `/sfu/get` and `/get_token` POST returned `400`, not `2xx` |

## LiveKit SFU

| Requirement | Result | Evidence bucket |
| --- | --- | --- |
| Service identified | PASS | `livekit-server` process present |
| Version known | UNKNOWN | binary/version inaccessible to audit user |
| Image pinned / immutable digest | UNKNOWN | Docker API inaccessible |
| Public WebSocket/TLS route | PASS | `rtc.mertis.kz` TLS valid; nginx proxies to LiveKit with WebSocket upgrade |
| `room.auto_create=false` | UNKNOWN | `/etc/livekit.yaml` not accessible from host namespace/audit user |
| Webhook configured | UNKNOWN | LiveKit config inaccessible |
| Webhook key matches SFU key | UNKNOWN | LiveKit config inaccessible |
| Auth-service key matches SFU key | UNKNOWN | LiveKit config and auth env inaccessible |
| Redis use | UNKNOWN | LiveKit config inaccessible |
| RTC transport mode | UNKNOWN | only ports `7880` and `7881` observed listening |
| TURN fallback | UNKNOWN | no TURN listener observed on common ports; config inaccessible |
| Public admin API exposure | FAIL_HIGH | LiveKit HTTP port `7880` is listening on all interfaces; whether firewall blocks direct access was not proven |

## Redis

| Requirement | Result | Evidence bucket |
| --- | --- | --- |
| Redis process present | PASS | `redis-server` process present |
| Redis persistence | UNKNOWN | config inaccessible |
| Redis not publicly exposed | FAIL_HIGH | Redis port `6379` is listening on all interfaces; whether firewall blocks direct access was not proven |

## Reverse Proxy And TLS

| Requirement | Result | Evidence bucket |
| --- | --- | --- |
| HTTPS enabled | PASS | matrix and rtc hosts have valid TLS certificates |
| `.well-known` JSON/CORS | PASS | `application/json`, CORS present |
| `/livekit/jwt/` route to auth service | FAIL_CRITICAL | advertised path returned `404`; nginx routes observed for `/sfu/get`, `/get_token`, `/healthz` instead |
| SFU WebSocket route | PASS | `rtc.mertis.kz` proxies to LiveKit with WebSocket upgrade |
| WebSocket Upgrade/Connection handling | PASS | route extraction found upgrade handling |
| Proxy buffering disabled for SFU/signaling | PASS | route extraction found `proxy_buffering off` |
| Proxy timeouts | PASS | route extraction found long read timeout |
| Debug MatrixRTC backend override exposed | UNKNOWN | not proven by allowlisted extraction |

## Network Exposure

| Port/service | Result |
| --- | --- |
| HTTPS `443` | public listener present |
| HTTP `80` | public listener present |
| Synapse federation `8448` | listener absent |
| Synapse client `8008` | localhost listener observed |
| SalemX call-service `8091` | localhost listener observed |
| LiveKit HTTP/signaling `7880` | all-interface listener observed |
| LiveKit RTC/TCP `7881` | all-interface listener observed |
| Redis `6379` | all-interface listener observed |
| TURN TLS `5349` | listener absent |
| TURN `3478` | listener absent |

Server-side firewall policy was not changed and was not fully provable from the unprivileged read-only account.

## SalemX Guardrails

| Check | Result |
| --- | --- |
| `salemx-call-service` active | PASS |
| `/dev/invite` | PASS, HTTP `404` |
| foreground `dev/invite` | PASS, HTTP `404` |
| unauthenticated foreground invite | PASS, POST returned `401` |
| unauthenticated foreground stream | PASS, GET returned `401` |
| unauthenticated foreground token | PASS, POST returned `401` |
| legacy direct token endpoint | NOT_APPLICABLE, returned `404` |
| APNs request | PASS, not performed |
| media connection | PASS, not performed |

## Redacted Log-Health Buckets

Recent limited journal windows were aggregated only:
- Synapse errorish bucket count: `0`
- nginx errorish bucket count: `0`
- SalemX call-service errorish bucket count: `0`

No raw log lines were copied.

## Findings By Severity

### FAIL_CRITICAL

1. MatrixRTC `.well-known` advertises `https://matrix.mertis.kz/livekit/jwt`, but the deployed nginx auth-service routes are `/sfu/get`, `/get_token`, and `/healthz`. The advertised focus URL returned `404`, so embedded Element Call clients cannot rely on the advertised MatrixRTC focus.

### FAIL_HIGH

1. LiveKit HTTP/signaling port `7880` is listening on all interfaces. Public firewall blocking was not proven.
2. Redis port `6379` is listening on all interfaces. Public firewall blocking was not proven.

### FAIL_MEDIUM

1. `matrix-synapse-mertis.service` is present and observed in an activating/auto-restart state.
2. Component pinning and immutable digests for `lk-jwt-service`, LiveKit, and Redis could not be proven because Docker inspection and process namespaces were inaccessible to the audit user.

### UNKNOWN Mandatory Requirements

1. MatrixRTC rate limits.
2. Delayed-event API availability by non-mutating proof.
3. MatrixRTC auth-service version and pinning.
4. `LIVEKIT_FULL_ACCESS_HOMESERVERS` restriction.
5. Auth-service Redis configuration.
6. Auth-service sanity-check interval.
7. Auth-service TLS verification bypass state.
8. LiveKit version and pinning.
9. `room.auto_create=false`.
10. LiveKit webhook validity.
11. SFU key matching.
12. TURN fallback readiness.
13. Debug MatrixRTC backend override absence.

## Remediation Candidates

No remediation was performed in Stage 1A. Candidate next steps:
1. Align `.well-known` `org.matrix.msc4143.rtc_foci[0].livekit_service_url` with the actual MatrixRTC Auth Service public route, or expose the advertised `/livekit/jwt` route correctly.
2. Prove or restrict public exposure for LiveKit HTTP/admin and Redis. Prefer localhost/container-network binds plus explicit reverse-proxy-only public routes.
3. Provide read-only audit access to container image metadata and sanitized config keys so versions, digests, `room.auto_create`, webhook, homeserver allowlist, Redis, sanity-check, and TLS verification state can be proven.
4. Investigate or remove the failing `matrix-synapse-mertis.service` if it is stale.
5. Add a documented read-only MatrixRTC audit command that emits only redacted keys and version/digest buckets.

## Stage 1A Gate

```text
local_head_expected=true
working_tree_clean_before=true
server_read_only_access=true
remote_mutation_detected=false
synapse_version_known=true
matrix_server_name_known=true
msc3266_enabled=true
msc4222_enabled=true
max_event_delay_24h=true
matrixrtc_rate_limits_valid=unknown
openid_or_federation_listener=true
well_known_valid=true
rtc_foci_valid=false
authorization_service_identified=true
authorization_service_pinned=unknown
full_access_homeservers_restricted=unknown
redis_configured=unknown
sanity_check_nonzero=unknown
tls_skip_verify_disabled=unknown
livekit_version_known=false
livekit_pinned=unknown
livekit_auto_create_disabled=unknown
livekit_webhook_valid=unknown
internal_ports_not_public=false
unauthenticated_token_issue=false
dev_invite_404=true
unauthenticated_invite_401=true
unauthenticated_stream_401=true
APNs_sent=false
media_connected=false
runtime_code_changed=false
server_changed=false
audit_document_created=true
commit_created=false
critical_findings=1
high_findings=2
unknown_mandatory_requirements=13
stage_1a_passed=false
```

## Privileged audit execution result

Stage: `1B-P2B`

Execution validation:
- Local baseline commit: `3b8951ba4a41a3dcfe79683e450a1073df74541b`
- Audit output file: present, regular, not a symlink, non-empty.
- `AUDIT_FORMAT_VERSION=1`: exactly one occurrence.
- `AUDIT_COMPLETE=true`: exactly one occurrence.
- `temporary_audit_file_removed=true`: exactly one occurrence.
- Required safety markers: `remote_configuration_changed=false`, `remote_services_restarted=false`, `firewall_changed=false`, `APNs_sent=false`, `media_connected=false`.
- Expected sections: all present exactly once.
- Duplicate conflicting keys: none.
- Secret/privacy scan: passed; no raw tokens, private keys, Matrix IDs, room IDs, APNs tokens, LiveKit secrets, Redis credentials, database credentials, auth headers, or complete environment arrays were imported.

### Complete redacted component findings

Deployment ownership:

| Component | Deployment | Active | Config source | Version / image bucket | Pinning bucket |
| --- | --- | --- | --- | --- | --- |
| Synapse | systemd | PASS | `/etc/matrix-synapse/homeserver.yaml` | `1.150.0` from Synapse section | NOT_APPLICABLE for image pinning |
| nginx | systemd | PASS | `/etc/nginx` | `nginx/1.18.0` | NOT_APPLICABLE for image pinning |
| SalemX call-service | systemd | PASS | systemd unit | version unknown | NOT_APPLICABLE for image pinning |
| MatrixRTC authorization service | docker | PASS | `/opt/matrixrtc/docker-compose.yml` | image tag `0.4.1`; direct version command did not produce a version | image pinned true |
| LiveKit SFU | docker | PASS | effective config source not proven | version `1.9.11`; image tag `master` | image pinned true |
| Redis | docker | PASS | `/opt/matrixrtc/docker-compose.yml` | image tag `7-alpine`; Redis version unknown | image pinned true |

Authorization service:

| Requirement | Privileged follow-up finding | Current classification |
| --- | --- | --- |
| Official MatrixRTC JWT service present | `authorization_service_official_lk_jwt=true` | PASS |
| Health endpoint | `authorization_health_status=200` | PASS |
| Internal bind safety | `authorization_bind_safe=true` | PASS |
| Full access homeservers restricted | exact `mertis` match true; wildcard false | PASS |
| LiveKit key and secret present | present true; values redacted | PASS |
| TLS skip verify disabled | `authorization_tls_skip_verify_disabled=true` | PASS |
| Unauthenticated token issuance | internal token probe returned `400`, not `2xx` | PASS |
| LiveKit URL matches expected target | `authorization_livekit_url_matches=false` | FAIL_MEDIUM |
| Auth-service key matches LiveKit key | `authorization_key_matches_livekit=false` | FAIL_MEDIUM |
| Auth-service Redis configuration | `authorization_redis_configured=false` | FAIL_MEDIUM |
| Sanity check interval non-zero | `authorization_sanity_check_nonzero=unknown` | UNKNOWN |
| Webhook route | `authorization_internal_webhook_status=404` | FAIL_MEDIUM |

LiveKit SFU:

| Requirement | Privileged follow-up finding | Current classification |
| --- | --- | --- |
| Service identified | docker container active | PASS |
| Version known | `livekit-server version 1.9.11` | PASS |
| Image pinned | `livekit_image_pinned=true` | PASS |
| Public WebSocket/TLS reverse proxy path | nginx SFU route present with WebSocket headers | PASS |
| Bind safety | `livekit_bind_safe=false`; port `7880` binds all interfaces | FAIL_HIGH |
| Effective config source | `livekit_config_source_known=false` | UNKNOWN |
| `room.auto_create=false` | `livekit_room_auto_create=unknown` | UNKNOWN |
| Webhook configured | `livekit_webhook_configured=false` | FAIL_MEDIUM |
| Webhook key/target validity | key and target match buckets unknown | UNKNOWN |
| Redis use | `livekit_redis_configured=false` | FAIL_MEDIUM |
| TURN fallback | `livekit_turn_mode=none`; TLS unavailable | FAIL_MEDIUM |
| UDP/RTC transport | UDP mux disabled, UDP range absent, TCP RTC disabled | FAIL_MEDIUM |

Redis:

| Requirement | Privileged follow-up finding | Current classification |
| --- | --- | --- |
| Service identified | docker container active | PASS |
| Auth-service uses Redis | `redis_authorization_service_uses=false` | FAIL_MEDIUM |
| LiveKit uses Redis | `redis_livekit_uses=false` | FAIL_MEDIUM |
| Bind safety | `redis_bind_safe=false`; port `6379` binds all interfaces | FAIL_HIGH |
| Auth/ACL/protected mode | unknown buckets | UNKNOWN |
| Persistence mode | `redis_persistence_mode=unknown` | UNKNOWN |

nginx and MatrixRTC focus:

| Requirement | Initial unprivileged finding | Privileged follow-up finding | Current classification |
| --- | --- | --- | --- |
| `.well-known` focus reaches auth service | advertised `/livekit/jwt` returned `404` | root cause still unknown; `jwt_location_present=false`; `/sfu` route present | UNKNOWN |
| `/sfu` route | observed in unprivileged route extraction | `sfu_location_present=true`, upstream loopback `7880` | PASS |
| `/livekit/jwt` route | advertised but 404 | `jwt_location_present=false` | FAIL_MEDIUM |
| WebSocket headers | present | present | PASS |
| Proxy buffering/timeouts | present | present | PASS |

Synapse:

| Requirement | Privileged follow-up finding | Current classification |
| --- | --- | --- |
| Version | `1.150.0` | PASS |
| Server name | `mertis` bucket true | PASS |
| MSC3266 | enabled true | PASS |
| MSC4222 | enabled true | PASS |
| Max event delay | `24h` true | PASS |
| OpenID or federation listener | true | PASS |
| MatrixRTC rate limits | aggregate valid bucket unknown; individual rate limit buckets unknown | UNKNOWN |

Network exposure distinction:

| Service | Process bind / publish evidence | Firewall / external reachability evidence | Current classification |
| --- | --- | --- | --- |
| MatrixRTC authorization internal port | not public | not needed | PASS |
| SalemX call-service internal port | not public | not needed | PASS |
| Synapse client `8008` | not public | not needed | PASS |
| LiveKit `7880` | bind-all true | firewall public unknown | FAIL_HIGH, actual public exposure unknown |
| Redis `6379` | bind-all true | firewall public unknown | FAIL_HIGH, actual public exposure unknown |

### Exact two high findings

1. `livekit_7880_bind_all_publication_not_fully_restricted`
   - Evidence: `livekit_bind_safe=false`, `livekit_7880_bind_all=true`, `livekit_7880_firewall_public=unknown`.
   - Actual internet exposure confirmed: unknown.
   - Remediation category: livekit.

2. `redis_6379_bind_all_publication_not_fully_restricted`
   - Evidence: `redis_bind_safe=false`, `redis_6379_bind_all=true`, `redis_6379_firewall_public=unknown`.
   - Actual internet exposure confirmed: unknown.
   - Remediation category: redis.

### Exact five remaining mandatory unknowns

1. `synapse_matrixrtc_rate_limits_valid`
   - Reason: unknown_value.
   - Blocking remediation: true.
   - Minimum required evidence: redacted read of Synapse rate-limit keys showing message and delayed-event management rate/burst values.

2. `authorization_sanity_check_nonzero`
   - Reason: unknown_value.
   - Blocking remediation: true.
   - Minimum required evidence: redacted authorization-service configuration or environment bucket proving a non-zero sanity-check interval.

3. `livekit_room_auto_create_false`
   - Reason: unknown_value.
   - Blocking remediation: true.
   - Minimum required evidence: redacted effective LiveKit config source proving `room.auto_create=false`.

4. `livekit_webhook_key_matches_authorization_key`
   - Reason: unknown_value.
   - Blocking remediation: true.
   - Minimum required evidence: redacted key-fingerprint comparison between effective LiveKit webhook key and authorization-service LiveKit key.

5. `livekit_webhook_target_matches_authorization_service`
   - Reason: unknown_value.
   - Blocking remediation: true.
   - Minimum required evidence: redacted effective LiveKit webhook URL target bucket matching the authorization-service webhook route.

The parsed audit summary reported `unknown_mandatory_requirements=5`, and these five findings are the corresponding mandatory unknowns. Additional non-mandatory Redis hardening buckets remain unknown (`redis_auth_or_acl_enabled`, `redis_protected_mode`, `redis_persistence_mode`) and should be included in a later hardening pass, but they are not counted in the five mandatory MatrixRTC gate unknowns imported here.

### Focus 404 result

```text
focus_404_root_cause_known=false
focus_404_root_cause=unknown
well_known_advertised_path=unknown
nginx_jwt_location=unknown
authorization_internal_expected_path=/sfu
```

Initial unprivileged finding: the client `.well-known` advertised `/livekit/jwt`, and that path returned `404`.

Privileged follow-up finding: nginx has the `/sfu` route and no JWT location, but the privileged output did not prove the advertised path from the effective `.well-known` value. The root cause therefore remains unknown rather than remediated.

Current classification: focus route evidence incomplete; do not remediate until a narrow follow-up proves the effective advertised path and the intended public authorization endpoint.

### Rollback baseline

Remediation file allowlist:

| File | Service | Reason | SHA-256 bucket |
| --- | --- | --- | --- |
| `/opt/matrixrtc/docker-compose.yml` | `lk-jwt-service` | authorization mandatory settings | `5fc62f41a2e17f6dac1bb27db36eedbe995e699566567e8194b194189fefa456` |
| `/etc/livekit.yaml` | `livekit` | LiveKit mandatory settings | unknown |
| `/etc/matrix-synapse/conf.d/91-matrixrtc.yaml` | `matrix-synapse` | Synapse MatrixRTC rate limits | `6fa0c998ea565791cd3510485327b51389ed90278163024d0b9d435e327b3722` |

```text
remediation_allowlist_complete=true
rollback_baseline_complete=false
livekit_hash_unknown_reason=unknown
```

The output names `/etc/livekit.yaml`, but the effective LiveKit config source is not proven (`livekit_config_source_known=false`) and the file hash is unknown. The output does not prove whether the path exists, whether it is regular or a symlink, whether it is mounted from another host path, or whether LiveKit receives config through arguments or environment. The rollback baseline is therefore incomplete.

### Minimum follow-up evidence required

Stage 1B-P is not complete because mandatory unknowns remain and rollback baseline is incomplete.

One narrow supplemental privileged read-only probe is required. It must not repeat the full audit and must only emit redacted buckets for:

1. Synapse MatrixRTC rate-limit values.
2. Authorization-service sanity-check interval.
3. Effective LiveKit config source, file type, mount source, and SHA-256 for the rollback file.
4. LiveKit `room.auto_create`.
5. LiveKit webhook URL target bucket and webhook key fingerprint comparison bucket.
6. Effective `.well-known` MatrixRTC advertised path and nginx authorization-route mapping.
7. Firewall/public reachability buckets for LiveKit `7880` and Redis `6379`, distinguishing bind-all from actual external exposure.

### Stage 1B-P2B gate

```text
local_head_expected=true
working_tree_clean_before=true
audit_output_present=true
audit_output_valid=true
audit_complete=true
temporary_remote_file_removed=true
secret_scan_passed=true
all_sections_present=true
high_findings_count=2
high_findings_exactly_classified=true
unknown_mandatory_requirements=5
unknown_count_consistent=true
focus_404_root_cause_known=false
remediation_allowlist_complete=true
rollback_baseline_complete=false
supplemental_privileged_probe_required=true
runtime_code_changed=false
server_accessed=false
server_changed=false
firewall_changed=false
APNs_sent=false
media_connected=false
audit_document_updated=true
commit_created=true
stage_1b_p2b_passed=true
```
