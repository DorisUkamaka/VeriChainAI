
;; title: VeriChainAI - AI Dataset Verification and Curation Platform
;; version: 1.0
;; summary: A decentralized marketplace for AI dataset curation and verification
;; description: Enables staking-based consensus for AI dataset quality assessment

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-DATASET-NOT-FOUND (err u101))
(define-constant ERR-INVALID-BOUNTY (err u102))
(define-constant ERR-DATASET-ALREADY-EXISTS (err u103))
(define-constant ERR-INVALID-METADATA (err u104))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-BOUNTY-AMOUNT u1000000) ;; 1 STX minimum bounty
(define-constant MAX-METADATA-LENGTH u255)

;; Data variables
(define-data-var next-dataset-id uint u1)
(define-data-var total-datasets uint u0)
(define-data-var platform-fee-rate uint u250) ;; 2.5% in basis points

;; Dataset data structure
(define-map datasets 
  uint 
  {
    provider: principal,
    dataset-hash: (buff 64),
    metadata-uri: (string-ascii 255),
    bounty-amount: uint,
    created-at: uint,
    status: (string-ascii 20), ;; "pending", "active", "completed"
    total-stake: uint,
    vote-count: uint
  }
)

;; Dataset provider tracking
(define-map provider-datasets principal (list 100 uint))

;; Public function to list a new dataset
(define-public (list-dataset (dataset-hash (buff 64)) (bounty-amount uint) (metadata-uri (string-ascii 255)))
  (let (
    (dataset-id (var-get next-dataset-id))
    (current-block block-height)
  )
    ;; Validate inputs
    (asserts! (>= bounty-amount MIN-BOUNTY-AMOUNT) ERR-INVALID-BOUNTY)
    (asserts! (> (len metadata-uri) u0) ERR-INVALID-METADATA)
    (asserts! (<= (len metadata-uri) MAX-METADATA-LENGTH) ERR-INVALID-METADATA)
    
    ;; Check if dataset hash already exists
    (asserts! (is-none (get-dataset-by-hash dataset-hash)) ERR-DATASET-ALREADY-EXISTS)
    
    ;; Transfer bounty from provider to contract
    (try! (stx-transfer? bounty-amount tx-sender (as-contract tx-sender)))
    
    ;; Store dataset
    (map-set datasets dataset-id {
      provider: tx-sender,
      dataset-hash: dataset-hash,
      metadata-uri: metadata-uri,
      bounty-amount: bounty-amount,
      created-at: current-block,
      status: "pending",
      total-stake: u0,
      vote-count: u0
    })
    
    ;; Update provider's dataset list
    (let ((current-list (default-to (list) (map-get? provider-datasets tx-sender))))
      (map-set provider-datasets tx-sender (unwrap! (as-max-len? (append current-list dataset-id) u100) ERR-INVALID-METADATA))
    )
    
    ;; Update counters
    (var-set next-dataset-id (+ dataset-id u1))
    (var-set total-datasets (+ (var-get total-datasets) u1))
    
    (ok dataset-id)
  )
)

;; Read-only function to get dataset by ID
(define-read-only (get-dataset (dataset-id uint))
  (map-get? datasets dataset-id)
)

;; Read-only function to get dataset by hash
(define-read-only (get-dataset-by-hash (dataset-hash (buff 64)))
  (let ((dataset-id (find-dataset-id-by-hash dataset-hash u1)))
    (if (is-some dataset-id)
      (map-get? datasets (unwrap-panic dataset-id))
      none
    )
  )
)

;; Read-only function to get provider's datasets
(define-read-only (get-provider-datasets (provider principal))
  (map-get? provider-datasets provider)
)

;; Read-only function to get total datasets count
(define-read-only (get-total-datasets)
  (var-get total-datasets)
)

;; Read-only function to get next dataset ID
(define-read-only (get-next-dataset-id)
  (var-get next-dataset-id)
)

;; Private function to find dataset ID by hash (helper function)
(define-private (find-dataset-id-by-hash (target-hash (buff 64)) (current-id uint))
  (let ((max-id (var-get next-dataset-id)))
    (if (>= current-id max-id)
      none
      (let ((dataset (map-get? datasets current-id)))
        (if (and (is-some dataset) (is-eq (get dataset-hash (unwrap-panic dataset)) target-hash))
          (some current-id)
          (find-dataset-id-by-hash target-hash (+ current-id u1))
        )
      )
    )
  )
)

