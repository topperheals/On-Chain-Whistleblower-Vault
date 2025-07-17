(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INVALID-STAKE (err u101))
(define-constant ERR-REPORT-NOT-FOUND (err u102))
(define-constant ERR-ALREADY-VERIFIED (err u103))
(define-constant ERR-INVALID-STATUS (err u104))
(define-constant MINIMUM-STAKE u1000000)

(define-data-var dao-admin principal tx-sender)
(define-data-var total-reports uint u0)
(define-data-var council-members (list 50 principal) (list))
(define-data-var member-to-remove principal tx-sender)

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
