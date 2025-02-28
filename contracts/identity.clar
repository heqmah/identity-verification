;; Decentralized Identity Verification Platform Smart Contract
;; This contract implements a decentralized identity system where:
;; 1. Certified validators can confirm user identities
;; 2. Users can submit their credentials for validation
;; 3. External services can verify a user's validation status
;; 4. Users retain control over their personal data

(define-constant admin-address tx-sender)

;; Error codes
(define-constant error-unauthorized (err u100))
(define-constant error-existing-validator (err u101))
(define-constant error-invalid-validator (err u102))
(define-constant error-identity-already-validated (err u103))
(define-constant error-identity-not-validated (err u104))
(define-constant error-invalid-trust-tier (err u105))
(define-constant error-not-admin (err u106))
(define-constant error-invalid-credential-hash (err u107))

;; Data structures
(define-map validators principal bool)
(define-map identity-records 
  { account: principal } 
  { 
    validated: bool, 
    trust-tier: uint, 
    validation-timestamp: uint, 
    credential-hash: (buff 32),
    validator: principal 
  }
)

;; Trust tiers
;; 1 = Standard validation
;; 2 = Enhanced validation
;; 3 = Complete validation

;; Read-only functions

;; Check if an address is a certified validator
(define-read-only (is-validator (address principal))
  (default-to false (get-validator-status address))
)

;; Get validator status
(define-read-only (get-validator-status (address principal))
  (map-get? validators address)
)

;; Check if an identity is validated
(define-read-only (is-identity-validated (account principal))
  (default-to false (get validated (get-identity-record account)))
)

;; Get identity validation details
(define-read-only (get-identity-record (account principal))
  (map-get? identity-records { account: account })
)

;; Get identity trust tier
(define-read-only (get-identity-trust-tier (account principal))
  (default-to u0 (get trust-tier (get-identity-record account)))
)

;; Helper function to validate trust tier
(define-private (is-valid-trust-tier (tier uint))
  (or (is-eq tier u1) (is-eq tier u2) (is-eq tier u3))
)

;; Helper function to validate credential hash (non-zero)
(define-private (is-valid-credential-hash (hash (buff 32)))
  (not (is-eq hash 0x0000000000000000000000000000000000000000000000000000000000000000))
)

;; Public functions

;; Register a new validator (only admin can do this)
(define-public (register-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender admin-address) error-unauthorized)
    (asserts! (not (is-validator validator)) error-existing-validator)
    (ok (map-set validators validator true))
  )
)

;; Deregister a validator (only admin can do this)
(define-public (deregister-validator (validator principal))
  (begin
    (asserts! (is-eq tx-sender admin-address) error-unauthorized)
    (asserts! (is-validator validator) error-invalid-validator)
    (ok (map-set validators validator false))
  )
)

;; Validate an identity (only certified validators can do this)
(define-public (validate-identity (account principal) (trust-tier uint) (credential-hash (buff 32)))
  (begin
    (asserts! (is-validator tx-sender) error-unauthorized)
    (asserts! (is-valid-trust-tier trust-tier) error-invalid-trust-tier)
    (asserts! (is-valid-credential-hash credential-hash) error-invalid-credential-hash)
    
    ;; Use a variable to store the sanitized identity data structure
    (let ((identity-entry { account: account })
          (validation-data { 
            validated: true, 
            trust-tier: trust-tier, 
            validation-timestamp: block-height, 
            credential-hash: credential-hash,
            validator: tx-sender 
          }))
      (ok (map-set identity-records identity-entry validation-data))
    )
  )
)

;; Revoke validation for an identity (can be done by the validator who validated the identity or admin)
(define-public (revoke-validation (account principal))
  (let ((current-record (unwrap! (get-identity-record account) error-identity-not-validated))
        (identity-entry { account: account })
        (revoked-data { 
          validated: false, 
          trust-tier: u0, 
          validation-timestamp: block-height, 
          credential-hash: 0x0000000000000000000000000000000000000000000000000000000000000000,
          validator: tx-sender 
        }))
    (begin
      (asserts! (or 
                 (is-eq tx-sender (get validator current-record))
                 (is-eq tx-sender admin-address)) 
                error-unauthorized)
      (ok (map-set identity-records identity-entry revoked-data))
    )
  )
)

;; Users can remove their own validation (self-revocation)
(define-public (revoke-own-validation)
  (let ((account tx-sender)
        (identity-entry { account: tx-sender })
        (revoked-data { 
          validated: false, 
          trust-tier: u0, 
          validation-timestamp: block-height, 
          credential-hash: 0x0000000000000000000000000000000000000000000000000000000000000000,
          validator: tx-sender 
        }))
    (begin
      (asserts! (is-identity-validated account) error-identity-not-validated)
      (ok (map-set identity-records identity-entry revoked-data))
    )
  )
)
