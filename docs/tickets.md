# Saved tickets and offline verification

Saved tickets let customers present a confirmed booking and venue staff verify it without internet. Offline verification is an [optional feature](requirements.md).

## Ticket issuance and verification

1. Once a reservation is confirmed, Seatwise issues a ticket that identifies the event and the booked seats. Seatwise signs the ticket data with its private signing key.
2. The customer signs in and saves the ticket while connected. Seatwise checks reservation ownership through the customer bearer token when delivering the ticket through the API. A downloadable ticket with a QR code is a first option. Apple Wallet and Google Wallet are potential ways to store and present the same admission credential.
3. The venue scanner loads Seatwise's trusted public verification key and its event configuration in advance. At the door, it checks the signature and confirms the ticket is for that event. The customer and scanner can both be offline during the check.

| Concern | Behavior |
| --- | --- |
| Ticket authenticity | Verify that Seatwise signed the presented ticket data and that the ticket is for the event being checked. |
| Repeat scans | The same ticket can pass verification again, including on re-entry. Verification has no admission counter, single-use rule or in/out tracking. |
| Ticket status | Offline checks use the ticket and the data available to the scanner. Refunds and revocation would need a way to deliver updated validity information if added later. |
| Online reservation access | [Customer authentication](auth.md) protects ticket delivery and reservation management. |
| Offline presentation | The scanner checks the ticket directly using its public verification key. A saved ticket carries admission information only and is independent of the customer's session or API token. |

## Questions to settle

- Does a reservation for several seats produce one group ticket or one ticket per seat?
- What information belongs on the ticket, and how does the venue scanner get the trusted key and expected event before doors open?
- Should offline ticket delivery support a download, a mobile wallet pass, or both?
