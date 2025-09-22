(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-STAKE (err u101))
(define-constant ERR-REPORT-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-VERIFIED (err u103))
(define-constant ERR-INVALID-STATUS (err u104))
(define-constant ERR-EVIDENCE-NOT-FOUND (err u105))
(define-constant ERR-INVALID-EVIDENCE (err u106))
(define-constant MINIMUM-STAKE u1000000)

(define-data-var dao-admin principal tx-sender)
(define-data-var total-reports uint u0)
(define-data-var council-members (list 50 principal) (list))
(define-data-var member-to-remove principal tx-sender)
(define-data-var total-evidence uint u0)

(define-map reports
    { report-id: uint }
    {
        reporter: (optional principal),
        encrypted-hash: (buff 256),
        stake-amount: uint,
        timestamp: uint,
        status: (string-ascii 20),
        verification-time: (optional uint),
    }
)

(define-map council-votes
    {
        report-id: uint,
        council-member: principal,
    }
    { voted: bool }
)

(define-map member-reputation
    { member: principal }
    {
        total-votes: uint,
        correct-votes: uint,
        reputation-score: uint,
        last-updated: uint,
    }
)

(define-map evidence-attachments
    { evidence-id: uint }
    {
        report-id: uint,
        evidence-hash: (buff 256),
        evidence-type: (string-ascii 50),
        submitter: (optional principal),
        timestamp: uint,
        file-size: uint,
        description: (string-ascii 500),
    }
)

(define-map report-evidence-count
    { report-id: uint }
    { count: uint }
)

(define-public (initialize-contract (admin principal))
    (begin
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (var-set dao-admin admin)
        (ok true)
    )
)

(define-public (add-council-member (member principal))
    (begin
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (var-set council-members
            (unwrap! (as-max-len? (append (var-get council-members) member) u50)
                ERR-NOT-AUTHORIZED
            ))
        (map-set member-reputation { member: member } {
            total-votes: u0,
            correct-votes: u0,
            reputation-score: u100,
            last-updated: stacks-block-height,
        })
        (ok true)
    )
)

(define-public (remove-council-member (member principal))
    (begin
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (var-set member-to-remove member)
        (var-set council-members
            (filter remove-member-check (var-get council-members))
        )
        (ok true)
    )
)

(define-private (remove-member-check (value principal))
    (not (is-eq value (var-get member-to-remove)))
)

(define-public (submit-report
        (encrypted-data (buff 256))
        (anonymous bool)
    )
    (let (
            (report-id (+ (var-get total-reports) u1))
            (reporter (if anonymous
                none
                (some tx-sender)
            ))
            (current-time stacks-block-height)
        )
        (asserts! (>= (stx-get-balance tx-sender) MINIMUM-STAKE)
            ERR-INVALID-STAKE
        )
        (try! (stx-transfer? MINIMUM-STAKE tx-sender (as-contract tx-sender)))
        (map-set reports { report-id: report-id } {
            reporter: reporter,
            encrypted-hash: encrypted-data,
            stake-amount: MINIMUM-STAKE,
            timestamp: current-time,
            status: "pending",
            verification-time: none,
        })
        (var-set total-reports report-id)
        (ok report-id)
    )
)

(define-public (verify-report (report-id uint))
    (let (
            (report (unwrap! (map-get? reports { report-id: report-id })
                ERR-REPORT-NOT-FOUND
            ))
            (is-council-member (is-some (index-of (var-get council-members) tx-sender)))
        )
        (asserts! is-council-member ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status report) "pending") ERR-INVALID-STATUS)
        (map-set council-votes {
            report-id: report-id,
            council-member: tx-sender,
        } { voted: true }
        )
        (ok true)
    )
)

(define-public (attach-evidence
        (report-id uint)
        (evidence-hash (buff 256))
        (evidence-type (string-ascii 50))
        (file-size uint)
        (description (string-ascii 500))
        (anonymous bool)
    )
    (let (
            (report (unwrap! (map-get? reports { report-id: report-id })
                ERR-REPORT-NOT-FOUND
            ))
            (evidence-id (+ (var-get total-evidence) u1))
            (submitter (if anonymous
                none
                (some tx-sender)
            ))
            (current-time stacks-block-height)
            (current-count (default-to { count: u0 }
                (map-get? report-evidence-count { report-id: report-id })
            ))
        )
        (asserts! (not (is-eq (get status report) "rejected")) ERR-INVALID-STATUS)
        (asserts! (> (len evidence-hash) u0) ERR-INVALID-EVIDENCE)
        (asserts! (> file-size u0) ERR-INVALID-EVIDENCE)
        (asserts! (> (len evidence-type) u0) ERR-INVALID-EVIDENCE)
        (map-set evidence-attachments { evidence-id: evidence-id } {
            report-id: report-id,
            evidence-hash: evidence-hash,
            evidence-type: evidence-type,
            submitter: submitter,
            timestamp: current-time,
            file-size: file-size,
            description: description,
        })
        (map-set report-evidence-count { report-id: report-id }
            { count: (+ (get count current-count) u1) }
        )
        (var-set total-evidence evidence-id)
        (ok evidence-id)
    )
)

(define-public (finalize-report
        (report-id uint)
        (approve bool)
    )
    (let (
            (report (unwrap! (map-get? reports { report-id: report-id })
                ERR-REPORT-NOT-FOUND
            ))
            (current-time stacks-block-height)
        )
        (asserts! (is-eq tx-sender (var-get dao-admin)) ERR-NOT-AUTHORIZED)
        (asserts! (is-eq (get status report) "pending") ERR-ALREADY-VERIFIED)
        (unwrap-panic (update-council-reputations report-id approve))
        (if approve
            (begin
                (match (get reporter report)
                    reporter (try! (as-contract (stx-transfer? (get stake-amount report) tx-sender reporter)))
                    true
                )
                (map-set reports { report-id: report-id }
                    (merge report {
                        status: "verified",
                        verification-time: (some current-time),
                    })
                )
            )
            (map-set reports { report-id: report-id }
                (merge report {
                    status: "rejected",
                    verification-time: (some current-time),
                })
            )
        )
        (ok true)
    )
)

(define-read-only (get-report (report-id uint))
    (map-get? reports { report-id: report-id })
)

(define-read-only (get-total-reports)
    (var-get total-reports)
)

(define-read-only (is-council-member (member principal))
    (is-some (index-of (var-get council-members) member))
)

(define-read-only (get-council-vote
        (report-id uint)
        (member principal)
    )
    (map-get? council-votes {
        report-id: report-id,
        council-member: member,
    })
)

(define-private (update-council-reputations (report-id uint) (final-decision bool))
    (begin
        (map update-member-reputation-helper
            (var-get council-members)
        )
        (ok true)
    )
)

(define-private (update-member-reputation-helper (member principal))
    (let (
            (vote-data (map-get? council-votes {
                report-id: (var-get total-reports),
                council-member: member,
            }))
            (current-reputation (default-to
                { total-votes: u0, correct-votes: u0, reputation-score: u100, last-updated: u0 }
                (map-get? member-reputation { member: member })
            ))
        )
        (if (is-some vote-data)
            (map-set member-reputation { member: member }
                (merge current-reputation {
                    total-votes: (+ (get total-votes current-reputation) u1),
                    correct-votes: (+ (get correct-votes current-reputation) u1),
                    reputation-score: (if (< (+ (get reputation-score current-reputation) u10) u1000)
                        (+ (get reputation-score current-reputation) u10)
                        u1000
                    ),
                    last-updated: stacks-block-height,
                })
            )
            (map-set member-reputation { member: member }
                (merge current-reputation {
                    reputation-score: (if (> (get reputation-score current-reputation) u10)
                        (- (get reputation-score current-reputation) u5)
                        u0
                    ),
                    last-updated: stacks-block-height,
                })
            )
        )
        member
    )
)

(define-read-only (get-member-reputation (member principal))
    (map-get? member-reputation { member: member })
)

(define-read-only (get-top-reputation-members)
    (var-get council-members)
)

(define-read-only (get-evidence (evidence-id uint))
    (map-get? evidence-attachments { evidence-id: evidence-id })
)

(define-read-only (get-report-evidence-count (report-id uint))
    (default-to { count: u0 }
        (map-get? report-evidence-count { report-id: report-id })
    )
)

(define-read-only (get-total-evidence)
    (var-get total-evidence)
)

(define-read-only (verify-evidence-hash
        (evidence-id uint)
        (provided-hash (buff 256))
    )
    (match (map-get? evidence-attachments { evidence-id: evidence-id })
        evidence (is-eq (get evidence-hash evidence) provided-hash)
        false
    )
)
