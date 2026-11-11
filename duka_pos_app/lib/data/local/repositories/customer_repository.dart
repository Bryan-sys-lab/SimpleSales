/// Repository for customers and credit.
///
/// Stub — Phase 3 extraction in progress. Delegates to DatabaseHelper for now;
/// Phase 4 will add transaction-aware variants for credit sales and payments.
class CustomerRepository {
  CustomerRepository._();
  static final CustomerRepository instance = CustomerRepository._();
}
