BEGIN;

CREATE TABLE IF NOT EXISTS salemx_direct_call_capabilities (
    capability_id UUID PRIMARY KEY,
    user_digest BYTEA NOT NULL CHECK (octet_length(user_digest) = 32),
    device_digest BYTEA NOT NULL CHECK (octet_length(device_digest) = 32),
    environment_digest BYTEA NOT NULL CHECK (octet_length(environment_digest) = 32),
    session_generation_digest BYTEA NOT NULL CHECK (octet_length(session_generation_digest) = 32),
    protocol_version INTEGER NOT NULL CHECK (protocol_version > 0),
    supported_intent TEXT NOT NULL CHECK (supported_intent IN ('audio')),
    handoff_classification TEXT NOT NULL CHECK (length(handoff_classification) BETWEEN 1 AND 64),
    token_binding_revision BIGINT NOT NULL CHECK (token_binding_revision >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    refreshed_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    CONSTRAINT salemx_direct_call_capabilities_active_binding_key UNIQUE
        (user_digest, device_digest, environment_digest, session_generation_digest, protocol_version, supported_intent),
    CONSTRAINT salemx_direct_call_capabilities_expiry_order CHECK (expires_at > created_at)
);

CREATE INDEX IF NOT EXISTS salemx_direct_call_capabilities_active_expiry_idx
    ON salemx_direct_call_capabilities (expires_at);

CREATE TABLE IF NOT EXISTS salemx_direct_call_dispatches (
    dispatch_id UUID PRIMARY KEY,
    sender_reference_digest BYTEA NOT NULL UNIQUE CHECK (octet_length(sender_reference_digest) = 32),
    receiver_reference_digest BYTEA NOT NULL UNIQUE CHECK (octet_length(receiver_reference_digest) = 32),
    metadata_nonce BYTEA NOT NULL CHECK (octet_length(metadata_nonce) = 12),
    encrypted_metadata BYTEA NOT NULL CHECK (octet_length(encrypted_metadata) > 16),
    sender_user_digest BYTEA NOT NULL CHECK (octet_length(sender_user_digest) = 32),
    sender_device_digest BYTEA NOT NULL CHECK (octet_length(sender_device_digest) = 32),
    sender_generation_digest BYTEA NOT NULL CHECK (octet_length(sender_generation_digest) = 32),
    receiver_user_digest BYTEA NOT NULL CHECK (octet_length(receiver_user_digest) = 32),
    receiver_device_digest BYTEA NOT NULL CHECK (octet_length(receiver_device_digest) = 32),
    receiver_generation_digest BYTEA NOT NULL CHECK (octet_length(receiver_generation_digest) = 32),
    receiver_token_binding_revision BIGINT NOT NULL CHECK (receiver_token_binding_revision >= 0),
    state TEXT NOT NULL CHECK (state IN (
        'prepared', 'claimed', 'sending', 'sent', 'consumed',
        'cancelled', 'expired', 'send_failed', 'delivery_unknown'
    )),
    row_version BIGINT NOT NULL DEFAULT 0 CHECK (row_version >= 0),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMPTZ NOT NULL,
    transitioned_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    send_attempt_count SMALLINT NOT NULL DEFAULT 0 CHECK (send_attempt_count IN (0, 1)),
    apns_outcome_bucket TEXT CHECK (apns_outcome_bucket IN ('accepted', 'rejected', 'unknown')),
    CONSTRAINT salemx_direct_call_dispatches_expiry_order CHECK (expires_at > created_at),
    CONSTRAINT salemx_direct_call_dispatches_attempt_state CHECK (
        (state IN ('prepared', 'claimed', 'cancelled') AND send_attempt_count = 0)
        OR (state IN ('sending', 'sent', 'consumed', 'send_failed', 'delivery_unknown') AND send_attempt_count = 1)
        OR (state = 'expired' AND send_attempt_count IN (0, 1))
    ),
    CONSTRAINT salemx_direct_call_dispatches_outcome_state CHECK (
        (state IN ('prepared', 'claimed', 'sending', 'cancelled') AND apns_outcome_bucket IS NULL)
        OR (state IN ('sent', 'consumed') AND apns_outcome_bucket = 'accepted')
        OR (state = 'send_failed' AND apns_outcome_bucket = 'rejected')
        OR (state = 'delivery_unknown' AND apns_outcome_bucket = 'unknown')
        OR (state = 'expired' AND apns_outcome_bucket IN ('accepted', 'unknown') OR state = 'expired' AND apns_outcome_bucket IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS salemx_direct_call_dispatches_active_expiry_idx
    ON salemx_direct_call_dispatches (expires_at)
    WHERE state IN ('prepared', 'claimed', 'sending', 'sent');

COMMIT;
