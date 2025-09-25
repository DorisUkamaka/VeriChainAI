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
(define-constant ERR-VOTING-STILL-ACTIVE (err u109))
(define-constant ERR-ALREADY-FINALIZED (err u110))
(define-constant ERR-NO-VOTES (err u111))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-BOUNTY-AMOUNT u1000000) ;; 1 STX minimum bounty
(define-constant MAX-METADATA-LENGTH u255)
(define-constant MIN-STAKE-AMOUNT u500000) ;; 0.5 STX minimum stake
(define-constant VOTING-PERIOD-BLOCKS u2016) ;; ~14 days at 10min/block
(define-constant MAX-QUALITY-SCORE u100)
(define-constant MIN-QUALITY-SCORE u0)
(define-constant CONSENSUS-THRESHOLD u10) ;; 10% deviation for consensus
(define-constant SLASHING-RATE u20) ;; 20% slashing for bad actors

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
    vote-count: uint,
  }
)

;; Dataset provider tracking
(define-map provider-datasets
  principal
  (list 100 uint)
)

;; Vote tracking structure
(define-map votes
  {
    dataset-id: uint,
    curator: principal,
  }
  {
    stake-amount: uint,
    quality-score: uint,
    accuracy-score: uint,
    bias-score: uint,
    documentation-score: uint,
    license-clarity-score: uint,
    justification: (string-ascii 500),
    voted-at: uint,
  }
)

;; Curator stakes per dataset
(define-map dataset-stakes
  uint
  (list 50 {
    curator: principal,
    amount: uint,
  })
)

;; Total curator stakes
(define-map curator-total-stakes
  principal
  uint
)

;; Final consensus scores for completed datasets
(define-map final-scores
  uint
  {
    overall-score: uint,
    quality-score: uint,
    accuracy-score: uint,
    bias-score: uint,
    documentation-score: uint,
    license-clarity-score: uint,
    total-rewards-distributed: uint,
    finalized-at: uint,
  }
)

;; Curator reputation tracking
(define-map curator-reputation
  principal
  {
    successful-votes: uint,
    total-votes: uint,
    total-rewards-earned: uint,
    reputation-score: uint,
  }
)

;; Public function to list a new dataset
(define-public (list-dataset
    (dataset-hash (buff 64))
    (bounty-amount uint)
    (metadata-uri (string-ascii 255))
  )
  (let (
      (dataset-id (var-get next-dataset-id))
      (current-block stacks-block-height)
    )
    ;; Validate inputs
    (asserts! (>= bounty-amount MIN-BOUNTY-AMOUNT) ERR-INVALID-BOUNTY)
    (asserts! (> (len metadata-uri) u0) ERR-INVALID-METADATA)
    (asserts! (<= (len metadata-uri) MAX-METADATA-LENGTH) ERR-INVALID-METADATA)

    ;; Note: Hash uniqueness could be enforced with additional data structures if needed

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
      vote-count: u0,
    })

    ;; Update provider's dataset list
    (let ((current-list (default-to (list) (map-get? provider-datasets tx-sender))))
      (map-set provider-datasets tx-sender
        (unwrap! (as-max-len? (append current-list dataset-id) u100)
          ERR-INVALID-METADATA
        ))
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

;; Note: get-dataset-by-hash removed to avoid circular dependencies
;; Users can query by dataset ID instead

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
      (current-block stacks-block-height)
    )
    ;; Validate inputs
    (asserts! (>= stake-amount MIN-STAKE-AMOUNT) ERR-INVALID-STAKE)
    (asserts! (<= current-block voting-deadline) ERR-VOTING-PERIOD-ENDED)
    (asserts!
      (is-none (map-get? votes {
        dataset-id: dataset-id,
        curator: tx-sender,
      }))
      ERR-ALREADY-VOTED
    )

    ;; Validate scores
    (asserts!
      (and (<= quality-score MAX-QUALITY-SCORE) (>= quality-score MIN-QUALITY-SCORE))
      ERR-INVALID-SCORE
    )
    (asserts!
      (and (<= accuracy-score MAX-QUALITY-SCORE) (>= accuracy-score MIN-QUALITY-SCORE))
      ERR-INVALID-SCORE
    )
    (asserts!
      (and (<= bias-score MAX-QUALITY-SCORE) (>= bias-score MIN-QUALITY-SCORE))
      ERR-INVALID-SCORE
    )
    (asserts!
      (and (<= documentation-score MAX-QUALITY-SCORE) (>= documentation-score MIN-QUALITY-SCORE))
      ERR-INVALID-SCORE
    )
    (asserts!
      (and (<= license-clarity-score MAX-QUALITY-SCORE) (>= license-clarity-score MIN-QUALITY-SCORE))
      ERR-INVALID-SCORE
    )

    ;; Transfer stake from curator to contract
    (try! (stx-transfer? stake-amount tx-sender (as-contract tx-sender)))

    ;; Record the vote
    (map-set votes {
      dataset-id: dataset-id,
      curator: tx-sender,
    } {
      stake-amount: stake-amount,
      quality-score: quality-score,
      accuracy-score: accuracy-score,
      bias-score: bias-score,
      documentation-score: documentation-score,
      license-clarity-score: license-clarity-score,
      justification: justification,
      voted-at: current-block,
    })

    ;; Update dataset stakes list
    (let ((current-stakes (default-to (list) (map-get? dataset-stakes dataset-id))))
      (map-set dataset-stakes dataset-id
        (unwrap!
          (as-max-len?
            (append current-stakes {
              curator: tx-sender,
              amount: stake-amount,
            })
            u50
          )
          ERR-INVALID-STAKE
        ))
    )

    ;; Update curator's total stakes
    (let ((current-total (default-to u0 (map-get? curator-total-stakes tx-sender))))
      (map-set curator-total-stakes tx-sender (+ current-total stake-amount))
    )

    ;; Update dataset totals
    (map-set datasets dataset-id
      (merge dataset {
        total-stake: (+ (get total-stake dataset) stake-amount),
        vote-count: (+ (get vote-count dataset) u1),
        status: "active",
      })
    )

    (ok true)
  )
)

;; Read-only function to get a vote
(define-read-only (get-vote
    (dataset-id uint)
    (curator principal)
  )
  (map-get? votes {
    dataset-id: dataset-id,
    curator: curator,
  })
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
      (<= stacks-block-height voting-deadline)
    )
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

;; Public function to finalize dataset and distribute rewards
(define-public (finalize-dataset (dataset-id uint))
  (let (
      (dataset (unwrap! (map-get? datasets dataset-id) ERR-DATASET-NOT-FOUND))
      (voting-deadline (+ (get created-at dataset) VOTING-PERIOD-BLOCKS))
      (stakes-list (default-to (list) (map-get? dataset-stakes dataset-id)))
    )
    ;; Validate conditions
    (asserts! (> stacks-block-height voting-deadline) ERR-VOTING-STILL-ACTIVE)
    (asserts! (is-none (map-get? final-scores dataset-id)) ERR-ALREADY-FINALIZED)
    (asserts! (> (get vote-count dataset) u0) ERR-NO-VOTES)

    ;; Calculate consensus scores
    (let (
        (consensus-result (calculate-consensus-scores dataset-id stakes-list))
        (overall-score (get overall-score consensus-result))
        (quality-score (get quality-score consensus-result))
        (accuracy-score (get accuracy-score consensus-result))
        (bias-score (get bias-score consensus-result))
        (documentation-score (get documentation-score consensus-result))
        (license-clarity-score (get license-clarity-score consensus-result))
        (total-rewards (+ (get bounty-amount dataset) (/ (get total-stake dataset) u10))) ;; bounty + 10% of stakes as rewards
      )
      ;; Store final scores
      (map-set final-scores dataset-id {
        overall-score: overall-score,
        quality-score: quality-score,
        accuracy-score: accuracy-score,
        bias-score: bias-score,
        documentation-score: documentation-score,
        license-clarity-score: license-clarity-score,
        total-rewards-distributed: total-rewards,
        finalized-at: stacks-block-height,
      })

      ;; Distribute rewards and update reputations
      (unwrap-panic (distribute-rewards dataset-id stakes-list consensus-result total-rewards))

      ;; Update dataset status
      (map-set datasets dataset-id (merge dataset { status: "completed" }))

      (ok overall-score)
    )
  )
)

;; Read-only function to get final scores
(define-read-only (get-final-scores (dataset-id uint))
  (map-get? final-scores dataset-id)
)

;; Read-only function to get curator reputation
(define-read-only (get-curator-reputation (curator principal))
  (default-to {
    successful-votes: u0,
    total-votes: u0,
    total-rewards-earned: u0,
    reputation-score: u0,
  }
    (map-get? curator-reputation curator)
  )
)

;; Private function to calculate consensus scores
(define-private (calculate-consensus-scores
    (dataset-id uint)
    (stakes-list (list 50 {
      curator: principal,
      amount: uint,
    }))
  )
  (let (
      (total-stake (fold add-stake-amounts stakes-list u0))
      (weighted-quality (fold add-weighted-quality stakes-list {
        sum: u0,
        dataset-id: dataset-id,
      }))
      (weighted-accuracy (fold add-weighted-accuracy stakes-list {
        sum: u0,
        dataset-id: dataset-id,
      }))
      (weighted-bias (fold add-weighted-bias stakes-list {
        sum: u0,
        dataset-id: dataset-id,
      }))
      (weighted-documentation (fold add-weighted-documentation stakes-list {
        sum: u0,
        dataset-id: dataset-id,
      }))
      (weighted-license (fold add-weighted-license stakes-list {
        sum: u0,
        dataset-id: dataset-id,
      }))
    )
    (let (
        (quality-consensus (/ (get sum weighted-quality) total-stake))
        (accuracy-consensus (/ (get sum weighted-accuracy) total-stake))
        (bias-consensus (/ (get sum weighted-bias) total-stake))
        (documentation-consensus (/ (get sum weighted-documentation) total-stake))
        (license-consensus (/ (get sum weighted-license) total-stake))
        (overall-consensus (/
          (+ quality-consensus accuracy-consensus bias-consensus
            documentation-consensus license-consensus
          )
          u5
        ))
      )
      {
        overall-score: overall-consensus,
        quality-score: quality-consensus,
        accuracy-score: accuracy-consensus,
        bias-score: bias-consensus,
        documentation-score: documentation-consensus,
        license-clarity-score: license-consensus,
      }
    )
  )
)

;; Private function to distribute rewards
(define-private (distribute-rewards
    (dataset-id uint)
    (stakes-list (list 50 {
      curator: principal,
      amount: uint,
    }))
    (consensus-scores {
      overall-score: uint,
      quality-score: uint,
      accuracy-score: uint,
      bias-score: uint,
      documentation-score: uint,
      license-clarity-score: uint,
    })
    (total-rewards uint)
  )
  (let ((platform-fee (/ (* total-rewards (var-get platform-fee-rate)) u10000)))
    (begin
      (fold distribute-curator-reward stakes-list {
        dataset-id: dataset-id,
        consensus-scores: consensus-scores,
        remaining-rewards: (- total-rewards platform-fee),
      })
      (ok true)
    )
  )
)

;; Private helper function for reward distribution
(define-private (distribute-curator-reward
    (stake-entry {
      curator: principal,
      amount: uint,
    })
    (context {
      dataset-id: uint,
      consensus-scores: {
        overall-score: uint,
        quality-score: uint,
        accuracy-score: uint,
        bias-score: uint,
        documentation-score: uint,
        license-clarity-score: uint,
      },
      remaining-rewards: uint,
    })
  )
  (let (
      (curator (get curator stake-entry))
      (stake-amount (get amount stake-entry))
      (dataset-id (get dataset-id context))
      (consensus (get consensus-scores context))
      (vote (unwrap-panic (map-get? votes {
        dataset-id: dataset-id,
        curator: curator,
      })))
    )
    (let (
        (curator-overall (/
          (+ (get quality-score vote) (get accuracy-score vote)
            (get bias-score vote) (get documentation-score vote)
            (get license-clarity-score vote)
          )
          u5
        ))
        (deviation (if (> curator-overall (get overall-score consensus))
          (- curator-overall (get overall-score consensus))
          (- (get overall-score consensus) curator-overall)
        ))
        (is-consensus (< deviation CONSENSUS-THRESHOLD))
        (reward-amount (if is-consensus
          (/ (* stake-amount u110) u100)
          (/ (* stake-amount (- u100 SLASHING-RATE)) u100)
        )) ;; 110% if good, 80% if bad
      )
      ;; Transfer reward/slashed amount
      (unwrap-panic (as-contract (stx-transfer? reward-amount tx-sender curator)))

      ;; Update curator reputation
      (let ((current-rep (get-curator-reputation curator)))
        (map-set curator-reputation curator {
          successful-votes: (if is-consensus
            (+ (get successful-votes current-rep) u1)
            (get successful-votes current-rep)
          ),
          total-votes: (+ (get total-votes current-rep) u1),
          total-rewards-earned: (+ (get total-rewards-earned current-rep) reward-amount),
          reputation-score: (if (> (get total-votes current-rep) u0)
            (/ (* (get successful-votes current-rep) u100)
              (get total-votes current-rep)
            )
            u0
          ),
        })
      )

      context
    )
  )
)

;; Private helper functions
(define-private (get-stake-amount (stake-entry {
  curator: principal,
  amount: uint,
}))
  (get amount stake-entry)
)

(define-private (add-stake-amounts
    (stake-entry {
      curator: principal,
      amount: uint,
    })
    (total uint)
  )
  (+ total (get amount stake-entry))
)

(define-private (add-weighted-quality
    (stake-entry {
      curator: principal,
      amount: uint,
    })
    (context {
      sum: uint,
      dataset-id: uint,
    })
  )
  (let ((vote (unwrap-panic (map-get? votes {
      dataset-id: (get dataset-id context),
      curator: (get curator stake-entry),
    }))))
    {
      sum: (+ (get sum context) (* (get quality-score vote) (get amount stake-entry))),
      dataset-id: (get dataset-id context),
    }
  )
)

(define-private (add-weighted-accuracy
    (stake-entry {
      curator: principal,
      amount: uint,
    })
    (context {
      sum: uint,
      dataset-id: uint,
    })
  )
  (let ((vote (unwrap-panic (map-get? votes {
      dataset-id: (get dataset-id context),
      curator: (get curator stake-entry),
    }))))
    {
      sum: (+ (get sum context) (* (get accuracy-score vote) (get amount stake-entry))),
      dataset-id: (get dataset-id context),
    }
  )
)

(define-private (add-weighted-bias
    (stake-entry {
      curator: principal,
      amount: uint,
    })
    (context {
      sum: uint,
      dataset-id: uint,
    })
  )
  (let ((vote (unwrap-panic (map-get? votes {
      dataset-id: (get dataset-id context),
      curator: (get curator stake-entry),
    }))))
    {
      sum: (+ (get sum context) (* (get bias-score vote) (get amount stake-entry))),
      dataset-id: (get dataset-id context),
    }
  )
)

(define-private (add-weighted-documentation
    (stake-entry {
      curator: principal,
      amount: uint,
    })
    (context {
      sum: uint,
      dataset-id: uint,
    })
  )
  (let ((vote (unwrap-panic (map-get? votes {
      dataset-id: (get dataset-id context),
      curator: (get curator stake-entry),
    }))))
    {
      sum: (+ (get sum context)
        (* (get documentation-score vote) (get amount stake-entry))
      ),
      dataset-id: (get dataset-id context),
    }
  )
)

(define-private (add-weighted-license
    (stake-entry {
      curator: principal,
      amount: uint,
    })
    (context {
      sum: uint,
      dataset-id: uint,
    })
  )
  (let ((vote (unwrap-panic (map-get? votes {
      dataset-id: (get dataset-id context),
      curator: (get curator stake-entry),
    }))))
    {
      sum: (+ (get sum context)
        (* (get license-clarity-score vote) (get amount stake-entry))
      ),
      dataset-id: (get dataset-id context),
    }
  )
)
