# 🛡️ On-Chain Whistleblower Vault

A secure and anonymous whistleblowing platform built on Stacks blockchain that enables confidential reporting of misconduct while maintaining transparency and protecting whistleblower identities.

## 🎯 Features

- Anonymous report submission with encrypted data
- DAO council verification system
- Stake-based spam prevention
- Time-stamped reports for auditability
- Refundable stakes for verified reports

## 📋 Contract Functions

### Administrative Functions
- `initialize-contract`: Set the DAO admin
- `add-council-member`: Add a member to the verification council
- `remove-council-member`: Remove a council member

### Reporting Functions
- `submit-report`: Submit an encrypted whistleblower report
- `verify-report`: Council members verify report validity
- `finalize-report`: Admin finalizes report status

### Read-Only Functions
- `get-report`: Retrieve report details
- `get-total-reports`: Get total number of submitted reports
- `is-council-member`: Check if an address is a council member
- `get-council-vote`: View council member votes

## 💎 Usage

1. Deploy contract
2. Initialize with DAO admin
3. Add council members
4. Submit encrypted reports with minimum stake
5. Council members verify reports
6. Admin finalizes reports and returns stakes if verified

## 🔒 Security

- Encrypted data stored on-chain
- Minimum stake requirement: 1,000,000 µSTX
- Multi-step verification process
- Anonymous reporting option

## 🤝 Contributing

Contributions welcome! Please submit PRs or open issues for improvements.
```
