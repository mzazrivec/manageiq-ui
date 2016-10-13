class ApplicationHelper::Button::RefreshWorkers < ApplicationHelper::Button::Basic
  needs :@record, :@lastaction

  def visible?
    !%w(download_logs evm_logs audit_logs).include?(@lastaction)
  end
end
