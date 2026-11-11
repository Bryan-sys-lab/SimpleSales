/// Repository for Open-profile jobs and cost pools.
///
/// Stub — Phase 3 extraction in progress. Delegates to DatabaseHelper for now;
/// Phase 4 will add transaction-aware variants for job completion and
/// cost-pool allocation.
class JobRepository {
  JobRepository._();
  static final JobRepository instance = JobRepository._();
}
