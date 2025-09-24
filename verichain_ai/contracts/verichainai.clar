
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
(define-constant ERR-INVALID-STAKE (err u105))
(define-constant ERR-ALREADY-VOTED (err u106))
(define-constant ERR-VOTING-PERIOD-ENDED (err u107))
(define-constant ERR-INVALID-SCORE (err u108))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-BOUNTY-AMOUNT u1000000) ;; 1 STX minimum bounty
(define-constant MAX-METADATA-LENGTH u255)
(define-constant MIN-STAKE-AMOUNT u500000) ;; 0.5 STX minimum stake
(define-constant VOTING-PERIOD-BLOCKS u2016) ;; ~14 days at 10min/block
(define-constant MAX-QUALITY-SCORE u100)
(define-constant MIN-QUALITY-SCORE u0)

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

;; Vote tracking structure
(define-map votes 
  {dataset-id: uint, curator: principal}
  {
    stake-amount: uint,
    quality-score: uint,
    accuracy-score: uint,
    bias-score: uint,
    documentation-score: uint,
    license-clarity-score: uint,
    justification: (string-ascii 500),
    voted-at: uint
  }
)

;; Curator stakes per dataset
(define-map dataset-stakes uint (list 50 {curator: principal, amount: uint}))

;; Total curator stakes
(define-map curator-total-stakes principal uint)

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

;; Public function to stake and vote on a dataset
(define-public (stake-and-vote 
  (dataset-id uint) 
  (stake-amount uint)
  (quality-score uint)
  (accuracy-score uint)
  (bias-score uint)
  (documentation-score uint)
  (license-clarity-score uint)
  (justification (string-ascii 500))
)
  (let (
    (dataset (unwrap! (map-get? datasets dataset-id) ERR-DATASET-NOT-FOUND))
    (voting-deadline (+ (get created-at dataset) VOTING-PERIOD-BLOCKS))
    (current-block block-height)
  )
    ;; Validate inputs
    (asserts! (>= stake-amount MIN-STAKE-AMOUNT) ERR-INVALID-STAKE)
    (asserts! (<= current-block voting-deadline) ERR-VOTING-PERIOD-ENDED)
    (asserts! (is-none (map-get? votes {dataset-id: dataset-id, curator: tx-sender})) ERR-ALREADY-VOTED)
    
    ;; Validate scores
    (asserts! (and (<= quality-score MAX-QUALITY-SCORE) (>= quality-score MIN-QUALITY-SCORE)) ERR-INVALID-SCORE)
    (asserts! (and (<= accuracy-score MAX-QUALITY-SCORE) (>= accuracy-score MIN-QUALITY-SCORE)) ERR-INVALID-SCORE)
    (asserts! (and (<= bias-score MAX-QUALITY-SCORE) (>= bias-score MIN-QUALITY-SCORE)) ERR-INVALID-SCORE)
    (asserts! (and (<= documentation-score MAX-QUALITY-SCORE) (>= documentation-score MIN-QUALITY-SCORE)) ERR-INVALID-SCORE)
    (asserts! (and (<= license-clarity-score MAX-QUALITY-SCORE) (>= license-clarity-score MIN-QUALITY-SCORE)) ERR-INVALID-SCORE)
    
    ;; Transfer stake from curator to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))
    
    ;; Record the vote
    (map-set votes {dataset-id: dataset-id, curator: tx-sender} {
      stake-amount: stake-amount,
      quality-score: quality-score,
      accuracy-score: accuracy-score,
      bias-score: bias-score,
      documentation-score: documentation-score,
      license-clarity-score: license-clarity-score,
      justification: justification,
      voted-at: current-block
    })
    
    ;; Update dataset stakes list
    (let ((current-stakes (default-to (list) (map-get? dataset-stakes dataset-id))))
      (map-set dataset-stakes dataset-id 
        (unwrap! (as-max-len? (append current-stakes {curator: tx-sender, amount: stake-amount}) u50) ERR-INVALID-STAKE))
    )
    
    ;; Update curator's total stakes
    (let ((current-total (default-to u0 (map-get? curator-total-stakes tx-sender))))
      (map-set curator-total-stakes tx-sender (+ current-total stake-amount))
    )
    
    ;; Update dataset totals
    (map-set datasets dataset-id (merge dataset {
      total-stake: (+ (get total-stake dataset) stake-amount),
      vote-count: (+ (get vote-count dataset) u1),
      status: "active"
    }))
    
    (ok true)
  )
)

;; Read-only function to get a vote
(define-read-only (get-vote (dataset-id uint) (curator principal))
  (map-get? votes {dataset-id: dataset-id, curator: curator})
)

;; Read-only function to get dataset stakes
(define-read-only (get-dataset-stakes (dataset-id uint))
  (map-get? dataset-stakes dataset-id)
)

;; Read-only function to get curator total stakes
(define-read-only (get-curator-total-stakes (curator principal))
  (default-to u0 (map-get? curator-total-stakes curator))
)

;; Read-only function to check if voting period is active
(define-read-only (is-voting-active (dataset-id uint))
  (match (map-get? datasets dataset-id)
    dataset (let ((voting-deadline (+ (get created-at dataset) VOTING-PERIOD-BLOCKS)))
              (<= block-height voting-deadline))
    false
  )
)

;; Read-only function to get voting deadline
(define-read-only (get-voting-deadline (dataset-id uint))
  (match (map-get? datasets dataset-id)
    dataset (some (+ (get created-at dataset) VOTING-PERIOD-BLOCKS))
    none
  )
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

