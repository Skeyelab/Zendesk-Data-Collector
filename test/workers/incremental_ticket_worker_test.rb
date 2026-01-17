require 'test_helper'

class IncrementalTicketWorkerTest < ActiveJob::TestCase
  test "enqueues incremental job" do
    assert_enqueued_with(job: IncrementalTicketJob) do
      IncrementalTicketJob.perform_later(123)
    end
  end
end
