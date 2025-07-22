;; Environmental Impact Tracking Contract
;; Measures and verifies carbon emission reductions

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-INVALID-DATA (err u501))
(define-constant ERR-PROJECT-NOT-FOUND (err u502))
(define-constant ERR-ALREADY-VERIFIED (err u503))
(define-constant ERR-INSUFFICIENT-CREDITS (err u504))

;; Data Variables
(define-data-var next-project-id uint u1)
(define-data-var next-credit-id uint u1)
(define-data-var total-carbon-reduced uint u0) ;; in kg CO2
(define-data-var carbon-price-per-kg uint u100) ;; microSTX per kg CO2

;; Data Maps
(define-map environmental-projects
  { project-id: uint }
  {
    owner: principal,
    project-name: (string-ascii 100),
    location: (string-ascii 100),
    project-type: (string-ascii 50), ;; solar, wind, hydro, etc.
    baseline-emissions: uint, ;; kg CO2 per year before project
    current-emissions: uint, ;; kg CO2 per year after project
    total-reduction: uint, ;; cumulative kg CO2 reduced
    status: (string-ascii 20),
    created-at: uint
  }
)

(define-map emission-records
  { project-id: uint, period: uint }
  {
    emissions-avoided: uint, ;; kg CO2 avoided this period
    energy-generated: uint, ;; kWh generated
    verification-status: (string-ascii 20),
    verifier: (optional principal),
    timestamp: uint,
    methodology: (string-ascii 100)
  }
)

(define-map carbon-credits
  { credit-id: uint }
  {
    project-id: uint,
    owner: principal,
    credits-amount: uint, ;; in kg CO2 equivalent
    price-per-credit: uint,
    status: (string-ascii 20), ;; active, retired, transferred
    created-at: uint,
    retired-at: (optional uint)
  }
)

(define-map verification-audits
  { project-id: uint, audit-period: uint }
  {
    auditor: principal,
    audit-result: (string-ascii 20), ;; passed, failed, pending
    emissions-verified: uint,
    audit-notes: (string-ascii 200),
    audit-date: uint
  }
)

(define-map sustainability-metrics
  { project-id: uint }
  {
    water-saved: uint, ;; liters per year
    land-preserved: uint, ;; square meters
    jobs-created: uint,
    community-benefit-score: uint, ;; 0-100
    biodiversity-impact: uint ;; 0-100 (positive impact)
  }
)

;; Read-only functions
(define-read-only (get-project (project-id uint))
  (map-get? environmental-projects { project-id: project-id })
)

(define-read-only (get-emission-record (project-id uint) (period uint))
  (map-get? emission-records { project-id: project-id, period: period })
)

(define-read-only (get-carbon-credit (credit-id uint))
  (map-get? carbon-credits { credit-id: credit-id })
)

(define-read-only (calculate-carbon-reduction (baseline uint) (current uint))
  (if (> baseline current)
    (ok (- baseline current))
    (ok u0)
  )
)

(define-read-only (get-project-impact (project-id uint))
  (match (map-get? environmental-projects { project-id: project-id })
    project (ok {
      total-reduction: (get total-reduction project),
      annual-reduction: (- (get baseline-emissions project) (get current-emissions project)),
      carbon-intensity: (if (> (get total-reduction project) u0)
        (/ (get total-reduction project) (- block-height (get created-at project)))
        u0)
    })
    (err ERR-PROJECT-NOT-FOUND)
  )
)

(define-read-only (get-sustainability-metrics (project-id uint))
  (map-get? sustainability-metrics { project-id: project-id })
)

;; Public functions
(define-public (register-project
  (project-name (string-ascii 100))
  (location (string-ascii 100))
  (project-type (string-ascii 50))
  (baseline-emissions uint)
)
  (let
    (
      (project-id (var-get next-project-id))
    )
    (asserts! (> baseline-emissions u0) ERR-INVALID-DATA)

    (map-set environmental-projects
      { project-id: project-id }
      {
        owner: tx-sender,
        project-name: project-name,
        location: location,
        project-type: project-type,
        baseline-emissions: baseline-emissions,
        current-emissions: baseline-emissions, ;; Initially same as baseline
        total-reduction: u0,
        status: "active",
        created-at: block-height
      }
    )

    (var-set next-project-id (+ project-id u1))

    (ok project-id)
  )
)

(define-public (record-emissions
  (project-id uint)
  (period uint)
  (emissions-avoided uint)
  (energy-generated uint)
  (methodology (string-ascii 100))
)
  (let
    (
      (project (unwrap! (map-get? environmental-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get owner project)) ERR-NOT-AUTHORIZED)
    (asserts! (> emissions-avoided u0) ERR-INVALID-DATA)
    (asserts! (> energy-generated u0) ERR-INVALID-DATA)

    (map-set emission-records
      { project-id: project-id, period: period }
      {
        emissions-avoided: emissions-avoided,
        energy-generated: energy-generated,
        verification-status: "pending",
        verifier: none,
        timestamp: block-height,
        methodology: methodology
      }
    )

    ;; Update project totals
    (map-set environmental-projects
      { project-id: project-id }
      (merge project {
        total-reduction: (+ (get total-reduction project) emissions-avoided)
      })
    )

    (var-set total-carbon-reduced (+ (var-get total-carbon-reduced) emissions-avoided))

    (ok emissions-avoided)
  )
)

(define-public (verify-emissions (project-id uint) (period uint))
  (let
    (
      (record (unwrap! (map-get? emission-records { project-id: project-id, period: period }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (is-eq (get verification-status record) "pending") ERR-ALREADY-VERIFIED)

    (map-set emission-records
      { project-id: project-id, period: period }
      (merge record {
        verification-status: "verified",
        verifier: (some tx-sender)
      })
    )

    (ok true)
  )
)

(define-public (generate-carbon-credits (project-id uint) (credits-amount uint))
  (let
    (
      (project (unwrap! (map-get? environmental-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
      (credit-id (var-get next-credit-id))
    )
    (asserts! (is-eq tx-sender (get owner project)) ERR-NOT-AUTHORIZED)
    (asserts! (> credits-amount u0) ERR-INVALID-DATA)
    (asserts! (<= credits-amount (get total-reduction project)) ERR-INSUFFICIENT-CREDITS)

    (map-set carbon-credits
      { credit-id: credit-id }
      {
        project-id: project-id,
        owner: tx-sender,
        credits-amount: credits-amount,
        price-per-credit: (var-get carbon-price-per-kg),
        status: "active",
        created-at: block-height,
        retired-at: none
      }
    )

    (var-set next-credit-id (+ credit-id u1))

    (ok credit-id)
  )
)

(define-public (transfer-carbon-credits (credit-id uint) (new-owner principal))
  (let
    (
      (credit (unwrap! (map-get? carbon-credits { credit-id: credit-id }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get owner credit)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status credit) "active") ERR-NOT-AUTHORIZED)

    (map-set carbon-credits
      { credit-id: credit-id }
      (merge credit { owner: new-owner })
    )

    (ok true)
  )
)

(define-public (retire-carbon-credits (credit-id uint))
  (let
    (
      (credit (unwrap! (map-get? carbon-credits { credit-id: credit-id }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get owner credit)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status credit) "active") ERR-NOT-AUTHORIZED)

    (map-set carbon-credits
      { credit-id: credit-id }
      (merge credit {
        status: "retired",
        retired-at: (some block-height)
      })
    )

    (ok true)
  )
)

(define-public (conduct-audit (project-id uint) (audit-period uint) (audit-result (string-ascii 20)) (emissions-verified uint) (audit-notes (string-ascii 200)))
  (let
    (
      (project (unwrap! (map-get? environmental-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
    )
    (map-set verification-audits
      { project-id: project-id, audit-period: audit-period }
      {
        auditor: tx-sender,
        audit-result: audit-result,
        emissions-verified: emissions-verified,
        audit-notes: audit-notes,
        audit-date: block-height
      }
    )

    (ok true)
  )
)

(define-public (update-sustainability-metrics
  (project-id uint)
  (water-saved uint)
  (land-preserved uint)
  (jobs-created uint)
  (community-benefit-score uint)
  (biodiversity-impact uint)
)
  (let
    (
      (project (unwrap! (map-get? environmental-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get owner project)) ERR-NOT-AUTHORIZED)
    (asserts! (<= community-benefit-score u100) ERR-INVALID-DATA)
    (asserts! (<= biodiversity-impact u100) ERR-INVALID-DATA)

    (map-set sustainability-metrics
      { project-id: project-id }
      {
        water-saved: water-saved,
        land-preserved: land-preserved,
        jobs-created: jobs-created,
        community-benefit-score: community-benefit-score,
        biodiversity-impact: biodiversity-impact
      }
    )

    (ok true)
  )
)

(define-public (update-carbon-price (new-price uint))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (> new-price u0) ERR-INVALID-DATA)

    (var-set carbon-price-per-kg new-price)

    (ok new-price)
  )
)

(define-public (update-project-emissions (project-id uint) (new-current-emissions uint))
  (let
    (
      (project (unwrap! (map-get? environmental-projects { project-id: project-id }) ERR-PROJECT-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get owner project)) ERR-NOT-AUTHORIZED)

    (map-set environmental-projects
      { project-id: project-id }
      (merge project { current-emissions: new-current-emissions })
    )

    (ok true)
  )
)
