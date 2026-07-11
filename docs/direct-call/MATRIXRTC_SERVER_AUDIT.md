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

## Authorization service upgrade assessment

Stage 1C-A audited the official `element-hq/lk-jwt-service` upstream release and tag evidence after the Stage 1B v5 rollback.

Primary sources used:

- Official repository and README: https://github.com/element-hq/lk-jwt-service
- Official releases: https://github.com/element-hq/lk-jwt-service/releases
- Official release-tag source snapshots: `v0.4.1`, `v0.4.2`, `v0.4.3`, `v0.4.4`, `v0.5.0`
- Official GHCR image metadata: `ghcr.io/element-hq/lk-jwt-service`

### Current deployed version

```text
current_authorization_image=ghcr.io/element-hq/lk-jwt-service:0.4.1
current_authorization_version=0.4.1
current_image_digest_present=true
sfu_get_supported=true
sfu_webhook_supported=false
authorization_service_upgrade_required=true
server_remediation_can_be_retried_without_version_upgrade=false
```

The post-rollback diagnostic proved that the active `0.4.1` deployment exposes `/sfu/get` but does not expose `/sfu_webhook`. That makes the previous v5 LiveKit webhook wiring invalid against the currently deployed authorization-service version.

### Candidate release matrix

Relevant published releases newer than `0.4.1`:

| Candidate | Published release | Image available | Immutable digest available | `/sfu/get` | `/sfu_webhook` | `LIVEKIT_REDIS_URL` | `LIVEKIT_SANITY_CHECK_INTERVAL_SECONDS` | `LIVEKIT_FULL_ACCESS_HOMESERVERS` | Key/secret compatibility | Host-network compatible | `/livekit/jwt/` proxy compatible | Breaking configuration changes | Migration required |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `0.4.2` | true | true | true | true | false | false | false | true | true | true | true | none in release notes | false for current config |
| `0.4.3` | true | true | true | true | false | false | false | true | true | true | true | LiveKit identity calculation changes for specific experimental modes | unknown, depends on Element Call mode |
| `0.4.4` | true | true | true | true | false | false | false | true | true | true | true | none for the current config; release updates signed JWT request handling | false for current config |
| `0.5.0` | true | true | true | true | false | false | false | true | true | true | true | `LIVEKIT_FULL_ACCESS_HOMESERVERS` is explicitly required and the old implicit wildcard fallback is removed | true if current deployment relied on implicit wildcard; otherwise false |

Release-tag source inspection is the decisive check here: the official release tags through `v0.5.0` do not contain `/sfu_webhook`, `LIVEKIT_REDIS_URL`, or `LIVEKIT_SANITY_CHECK_INTERVAL_SECONDS`. Those features are present in the current `main` branch README/source, but Stage 1C-A must not select an unreleased `main` build or a floating tag.

```text
published_compatible_release_available=false
source_build_or_wait_required=true
selected_version=none
selected_image=none
selected_image_digest=unknown
image_architecture_compatible=unknown
image_pinned=false
floating_tag_required=false
```

No published release currently satisfies all mandatory SalemX MatrixRTC authorization-service requirements.

### Image metadata

The official release notes publish GHCR image tags for `0.4.2`, `0.4.3`, `0.4.4`, and `0.5.0`. Read-only manifest inspection showed OCI image indexes with `linux/amd64` and `linux/arm64` entries, plus attestation manifests, for those tags. No image was pulled.

Because no compatible published release exists, Stage 1C-A does not select a tag or digest. A future remediation must pin an immutable image reference only after a published compatible release exists.

### Configuration compatibility

Existing settings that remain compatible across the audited release tags:

```text
LIVEKIT_URL=compatible
LIVEKIT_KEY=compatible
LIVEKIT_KEY_FROM_FILE=compatible
LIVEKIT_SECRET=compatible
LIVEKIT_SECRET_FROM_FILE=compatible
LIVEKIT_KEY_FILE=compatible
LIVEKIT_JWT_BIND=compatible
LIVEKIT_JWT_PORT=deprecated_but_supported
network_mode=host=compatible
reverse_proxy_path=/livekit/jwt/=compatible_with_proxy_path_stripping
```

Required SalemX additions that are not available in any published compatible release:

```text
LIVEKIT_REDIS_URL=redis://127.0.0.1:6379
LIVEKIT_SANITY_CHECK_INTERVAL_SECONDS=60
```

`0.5.0` additionally requires `LIVEKIT_FULL_ACCESS_HOMESERVERS` to be set explicitly. This is a secure default change, but it does not solve the missing webhook or Redis persistence requirements.

### Endpoint acceptance rules

For a future compatible authorization-service release, acceptance checks must validate route existence rather than requiring success from unsigned or unauthenticated requests:

```text
GET /sfu/get = method rejection or auth/input rejection, but not 404
POST /sfu/get with empty JSON = input/auth rejection, but not 404
POST /sfu_webhook unsigned = signature/input rejection, but not 404
```

Do not require `/health` unless the selected release officially implements it. The current release-tag README documents `/healthz`, not `/health`.

### Rollback strategy

Do not retry the Stage 1B server remediation against `0.4.1`. For a future published compatible release:

1. Pin the exact GHCR image tag and immutable digest.
2. Preserve the current LiveKit API key/secret and homeserver allowlist.
3. Add only the required authorization environment values and LiveKit webhook wiring.
4. Apply changes in the existing safe order: Synapse restart, LiveKit-only recreation, authorization-service-only recreation.
5. On any post-installation failure after file replacement, restore the exact three rollback file hashes and recreate only the services touched by the staged remediation. Do not restart Redis, nginx, or `salemx-call-service`.

### Salem call-service route-contract finding

The post-rollback diagnostic reported:

```text
invite_route_classified_method=GET
invite_route_status=400
stream_route_classified_method=GET
stream_route_status=404
salem_guardrail_result_reliable=false
reason=method_or_route_discovery_conflicts_with_previous_confirmed_contract
```

This is a separate SalemX call-service route-contract issue. Do not include `salemx-call-service` in the authorization-service upgrade. A narrow route-contract audit must follow separately.

### Stage 1C-A gate

```text
current_version_confirmed=true
webhook_missing_confirmed=true
published_releases_audited=true
published_compatible_release_available=false
selected_version=none
selected_image_digest_known=false
image_architecture_compatible=unknown
configuration_compatibility_known=true
floating_tag_required=false
server_accessed=false
server_changed=false
image_pulled=false
runtime_code_changed=false
audit_document_updated=true
```

## Pinned upstream source candidate qualification

Stage 1C-B evaluated the official upstream source candidate:

```text
candidate_repository=https://github.com/element-hq/lk-jwt-service.git
candidate_commit=ac7d0de49060b0cabe25925c4b671d5e8f637567
candidate_status=source_features_present_but_local_qualification_blocked
deployment_status=not_installed
```

The local clone was checked out in detached-HEAD mode at the exact candidate commit. No branch name such as `main` was used for build or test selection after checkout.

### Provenance

```text
origin_url_exact=true
candidate_commit_exists=true
candidate_commit_exact=ac7d0de49060b0cabe25925c4b671d5e8f637567
detached_head=true
working_tree_clean=true
v0_5_0_commit=199ac87dbbf704320b277aebdf10a6280b18c77d
candidate_descends_from_v0_5_0=true
commits_after_v0_5_0=13
author_bucket=upstream_external_contributor
commit_date=2026-07-10T17:08:43+02:00
commit_subject=Add black-box tests for LIVEKIT_INSECURE_SKIP_VERIFY_TLS (#199)
parent_sha=a3ae883e62ed54a53535a1157679dd579f06bf4d
tree_sha=074b7826670cf21aad7773302814180eac8fd7cd
commit_signature_status=unknown
```

The commit contains a signature block, but local Git did not prove a valid signature because local signature verification could not complete with trusted key material. This is recorded as `unknown`, not valid.

### Feature proof

Feature support was proven from candidate source and tests, not from README alone:

| Feature | Source present | Tests present | Proof bucket |
| --- | --- | --- | --- |
| `/sfu/get` | true | true | `handler.go`, `requests.go`, `sfu_get_test.go`, integration tests |
| `/sfu_webhook` | true | true | `handler.prepareMux`, `handleSfuWebhook`, `handler_test.go` |
| `LIVEKIT_REDIS_URL` | true | true | `config.go`, `main.go`, `store.go`, `config_test.go`, `store_test.go` |
| `LIVEKIT_SANITY_CHECK_INTERVAL_SECONDS` | true | true | `config.go`, `delayedEventManager.go`, `config_test.go`, `delayedEventManager_test.go` |
| `LIVEKIT_FULL_ACCESS_HOMESERVERS` | true | true | `config.go`, `handler.go`, `config_test.go` |
| `LIVEKIT_URL` | true | true | `config.go`, token endpoint tests |
| `LIVEKIT_KEY` | true | true | `config.go`, token/webhook tests |
| `LIVEKIT_SECRET` | true | true | `config.go`, token/webhook tests |
| `LIVEKIT_JWT_BIND` | true | true | `config.go`, `config_test.go`, integration harness |

Additional verified behavior:

```text
sfu_webhook_route_registration=true
sfu_webhook_post_handling=true
sfu_webhook_livekit_signature_verification=true
sfu_webhook_delegated_leave_integration=true
sfu_webhook_invalid_unsigned_payload_rejected=true
redis_state_backend_selection=true
redis_persistence_restore_behavior=true
redis_unset_fallback_to_in_memory=true
redis_credentials_not_required_when_url_has_none=true
sanity_check_unset_or_zero_disables=true
sanity_check_positive_seconds_enables=true
sanity_check_fallback_for_missed_sfu_lifecycle_events=true
```

### Change scope from `v0.5.0`

```text
commits_changed=13
files_added=29
files_modified=10
files_deleted=1
total_additions=11767
total_deletions=2151
```

Changed areas:

```text
configuration=true
HTTP_routing=true
delegated_leave=true
storage=true
Redis=true
tests=true
integration_tests=true
Dockerfile_build=true
dependencies=true
CI_workflows=true
```

Compatibility assessment:

```text
breaking_config_change_detected=true
existing_0_4_1_environment_compatible=unknown
existing_nginx_path_compatible=true
host_network_compatible=true
```

Risk note: from `v0.5.0` to the candidate, the source adds delegated leave, Redis-backed state, sanity checks, new integration tests, Dockerfile changes, dependency updates, and CI changes. The candidate still supports the existing core settings (`LIVEKIT_URL`, LiveKit key/secret, `LIVEKIT_FULL_ACCESS_HOMESERVERS`, `LIVEKIT_JWT_BIND`) and keeps reverse-proxy path stripping compatible because the service exposes root-relative routes such as `/sfu/get` and `/sfu_webhook`. The effective `0.4.1` production environment remains `unknown` until the upgrade script validates exact active environment keys before mutation.

### Dependency and build metadata

```text
go_version=1.26
go_toolchain=go1.26.4
builder_base_image=docker.io/golang:${GO_VERSION}-alpine
runtime_base_image=scratch
base_images_digest_pinned=false
dependency_replace_directives_present=false
local_path_dependencies_present=false
govulncheck_available=false
govulncheck_result=not_run
```

Direct Go modules:

```text
github.com/SladkyCitron/slogcolor v1.9.0
github.com/alicebob/miniredis/v2 v2.38.0
github.com/cenkalti/backoff/v5 v5.0.3
github.com/golang-jwt/jwt/v5 v5.3.1
github.com/livekit/protocol v1.48.1-0.20260624204523-bd5703442db6
github.com/livekit/server-sdk-go/v2 v2.16.7
github.com/matrix-org/gomatrix v0.0.0-20220926102614-ceba4d9f7530
github.com/matrix-org/gomatrixserverlib v0.0.0-20260506075950-c9c468727353
github.com/mattn/go-isatty v0.0.22
github.com/redis/go-redis/v9 v9.21.0
github.com/twitchtv/twirp v8.1.3+incompatible
google.golang.org/protobuf v1.36.11
maunium.net/go/mautrix v0.28.1
```

### Upstream validation commands

Official workflow inspection found:

```text
upstream_unit_test_command=go test -timeout 30s
upstream_integration_test_command=cargo test --locked
upstream_lint_provider=golangci/golangci-lint-action
```

Local command results:

| Command | Result | Reason |
| --- | --- | --- |
| `go test ./...` | blocked | `go` not installed locally |
| `go test -timeout 30s` | blocked | `go` not installed locally |
| `go vet ./...` | blocked | `go` not installed locally |
| `golangci-lint run` | blocked | `golangci-lint` not installed locally |
| `govulncheck ./...` | not_run | `govulncheck` not installed locally |
| `cargo test --locked` | blocked | integration harness builds the service and requires local `go` |

Required unit tests did not pass in this environment because they could not run.

### Server architecture and local build gate

The only server command executed in Stage 1C-B was the authorized read-only architecture query:

```text
server_architecture=x86_64
target_platform=linux/amd64
server_accessed_read_only=true
server_changed=false
```

Local build tooling:

```text
docker_available=true
docker_buildx_available=true
docker_daemon_available=false
docker_daemon_blocker=unix_socket_missing
```

Because required source tests did not pass and the Docker daemon was unavailable, the local image build, local smoke, and image export gates were not executed.

```text
image_build_success=false
image_repository=salemx/lk-jwt-service
image_tag=ac7d0de49060b0cabe25925c4b671d5e8f637567
image_platform=linux/amd64
image_id=unknown
image_repo_digest=none
binary_starts=false
controlled_missing_config_failure=false
unexpected_panic=false
archive_created=false
archive_sha256=unknown
archive_size_bytes=0
archive_regular_file=false
archive_symlink=false
```

### External manifest

An external, non-secret manifest was created outside the repository:

```text
manifest_path=/tmp/salemx-lk-jwt-service-ac7d0de49060b0cabe25925c4b671d5e8f637567.manifest.txt
manifest_mode=0600
manifest_created=true
manifest_status=blocked
```

No image archive was created or copied to the server.

### Configuration compatibility

Expected future configuration for this candidate remains:

```text
LIVEKIT_URL=current_value_preserved
LIVEKIT_KEY=current_value_or_file_equivalent_preserved
LIVEKIT_SECRET variable current value or file equivalent preserved
LIVEKIT_FULL_ACCESS_HOMESERVERS=current_allowlist_preserved
LIVEKIT_JWT_BIND=current_bind_preserved
LIVEKIT_REDIS_URL=redis://127.0.0.1:6379
LIVEKIT_SANITY_CHECK_INTERVAL_SECONDS=60
network_mode=host
nginx_public_prefix=/livekit/jwt/
```

Endpoint acceptance for a future installed build:

```text
POST /sfu/get=not_404_for_route_existence
POST /sfu_webhook_unsigned=signature_or_input_rejection_but_not_404
GET /healthz=200_if_service_started
```

### Stage 1C-B gate

```text
local_head_expected=true
working_tree_clean_before=true
official_origin_verified=true
candidate_commit_exact=true
detached_head=true
candidate_descends_from_v0_5_0=true
required_features_source_proven=true
required_features_tests_proven=true
change_scope_audited=true
configuration_compatibility_known=true
required_unit_tests_passed=false
required_integration_tests_passed=false
server_architecture_known=true
target_platform_known=true
docker_build_available=false
local_image_built=false
local_image_id_known=false
local_smoke_passed=false
archive_created=false
archive_sha256_known=false
manifest_created=true
secret_scan_passed=true
server_accessed_read_only=true
server_changed=false
image_installed_on_server=false
runtime_code_changed=false
audit_document_updated=true
commit_created=false
stage_1c_b_passed=false
```

### Stage 1C-B2 resumed qualification

Initial qualification attempt: blocked by unavailable local toolchain.

Resumed qualification: passed. Stage 1C-B2 used temporary tooling under `/tmp`, kept the candidate source clean, built only a local `linux/amd64` image, exported it to a local archive, and did not install or transfer the image to the server.

Baseline and dirty-path allowance:

```text
local_head_expected=true
initial_dirty_paths=docs/direct-call/MATRIXRTC_SERVER_AUDIT.md
preexisting_dirty_path_allowed=true
unexpected_dirty_paths_present=false
```

Docker gate:

```text
docker_cli_available=true
docker_buildx_available=true
docker_daemon_available=true
docker_client_version=29.4.2
docker_server_version=29.4.2
docker_daemon_platform=linux/aarch64
```

Temporary Go toolchain:

```text
go_archive_official=true
go_archive=go1.26.4.darwin-arm64.tar.gz
go_archive_sha256=b62ad2b6d7d2464f12a5bcad7ff47f19d08325773b5efd21610e445a05a9bf53
go_archive_sha256_verified=true
temporary_go_version=go version go1.26.4 darwin/arm64
system_go_modified=false
```

Candidate source integrity:

```text
origin=https://github.com/element-hq/lk-jwt-service.git
candidate_commit=ac7d0de49060b0cabe25925c4b671d5e8f637567
detached_head=true
candidate_source_clean_before=true
candidate_source_clean_after=true
go_mod_unchanged=true
go_sum_unchanged=true
```

Verified source hashes:

```text
go.mod=589f37b8acb9c310330f4e02a06ec213988cc49642506afafaaadee0c61e095b
go.sum=3f9cc679088432be2ec09f2c82725ac4935a89a20a4f099f494051b5d63f75de
Dockerfile=90500ce06cbabb83020cf11292e7371a6528547d183e083c17f095fecacaa7d5
.github/workflows/test.yaml=25402ef9306a1009b8aa1590773a61c7d3838b2c21499866fb1a54a9d8f6ee5d
.github/workflows/lint.yaml=84832e46a03cd3d60016b9ab5e35c6e51676b79ecdbd1f2dae618e421b687b8b
integration-tests/Cargo.lock=792f50f25fb6ea415d838cabe5d5c6eba5b7a9fd67e5ddaebf6df2936c3173ff
```

Unit, vet, lint, and integration results:

| Command | Result | Notes |
| --- | --- | --- |
| `go test -timeout 30s` | pass | official upstream unit command |
| `go test ./...` | pass | rerun outside sandbox after local `httptest` bind denial |
| `go vet ./...` | pass | temporary Go toolchain |
| `golangci-lint run` | pass | pinned container image, `0 issues` |
| `cargo test --locked` | pass | local fake homeserver/SFU integration suite |

Lint resolution:

```text
upstream_lint_action=golangci/golangci-lint-action@82606bf257cbaff209d206a39f5134f0cfbfd2ee
lint_workflow_version_input_absent=true
lint_action_latest_resolved_version=v2.12.2
lint_image=docker.io/golangci/golangci-lint:v2.12.2
lint_image_index_digest=sha256:5cceeef04e53efe1470638d4b4b4f5ceefd574955ab3941b2d9a68a8c9ad5240
golangci_lint_result=pass
```

Integration tooling:

```text
cargo_available=true
cargo_version=cargo 1.93.1 (083ac5135 2025-12-15)
rustc_version=rustc 1.93.1 (01f6ddf75 2026-02-11)
integration_tests_passed=true
production_credentials_used=false
salemx_server_used=false
```

Builder image proof:

```text
builder_image_tag=docker.io/library/golang:1.26.4-alpine
builder_image_index_digest=sha256:3ad57304ad93bbec8548a0437ad9e06a455660655d9af011d58b993f6f615648
builder_image_linux_amd64_digest=sha256:0648ddfa35769070197ba1cdf22a16dc452caf9315e66b91791308a543baf229
builder_image_digest_known=true
```

Local image:

```text
image_build_success=true
image_repository=salemx/lk-jwt-service
image_tag=ac7d0de49060b0cabe25925c4b671d5e8f637567
image_platform=linux/amd64
image_config_id=sha256:bec25a1453bb42f6f766ae884ae325fc00995b726dd692cbcd8cc3dc3f369613
image_manifest_digest=sha256:0e61037b9558724c3eccbd50386af1e682881e0c7ffb4c81d153f87f81fe5aaf
image_index_digest=sha256:bd9f2c8e286a718ea72f22347ca6748e403415896be71509a032be70da07ece4
docker_reported_image_id=sha256:bd9f2c8e286a718ea72f22347ca6748e403415896be71509a032be70da07ece4
image_repo_digest=salemx/lk-jwt-service@sha256:bd9f2c8e286a718ea72f22347ca6748e403415896be71509a032be70da07ece4
image_identity_note=Docker reports the OCI index digest as .Id for this loaded multi-platform archive; the per-platform linux/amd64 image config ID is recorded separately.
entrypoint_or_cmd_expected=true
exposed_port_8080=true
healthcheck_present=true
unexpected_environment_values=false
embedded_secrets=false
```

Local smoke:

```text
image_platform_confirmed=linux/amd64
healthcheck_binary_invoked=true
binary_starts=true
controlled_missing_config_failure=true
unexpected_panic=false
public_port_published=false
smoke_containers_remaining=false
```

Exported artifact:

```text
archive_path=/tmp/salemx-lk-jwt-service-ac7d0de49060b0cabe25925c4b671d5e8f637567.tar
archive_regular_file=true
archive_symlink=false
archive_mode=0600
archive_sha256=c4cafbc2f08c60f7b83c0e4abb6bed1b7a0af63d1cf03409b894d8c36fabfd0d
archive_size_bytes=24259584
```

External manifest:

```text
manifest_path=/tmp/salemx-lk-jwt-service-ac7d0de49060b0cabe25925c4b671d5e8f637567.manifest.txt
manifest_mode=0600
manifest_status=passed
manifest_created=true
```

Deployment status:

```text
server_accessed_read_only=false
server_changed=false
image_installed_on_server=false
server_container_changed=false
runtime_code_changed=false
APNs_sent=false
media_connected=false
```

### Stage 1C-B2 gate

```text
local_head_expected=true
preexisting_dirty_path_allowed=true
unexpected_dirty_paths_present=false
docker_daemon_available=true
temporary_go_exact_version=true
go_archive_sha256_verified=true
candidate_commit_exact=true
candidate_source_clean_before=true
official_unit_test_passed=true
go_test_all_passed=true
go_vet_passed=true
golangci_lint_result=pass
integration_tests_passed=true
candidate_source_clean_after=true
builder_image_digest_known=true
local_image_built=true
local_image_platform_correct=true
local_smoke_passed=true
archive_created=true
archive_sha256_known=true
manifest_created=true
secret_scan_passed=true
server_accessed_read_only=false
server_changed=false
image_installed_on_server=false
runtime_code_changed=false
audit_document_updated=true
commit_created=true
stage_1c_b2_passed=true
```
