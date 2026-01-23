class DashboardController < ApplicationController
  before_action :authenticate_admin_user!

  def index
    @total_tickets = ZendeskTicket.count
    @active_desks = Desk.where(active: true).count
    # Try multiple resolution time fields, fallback to calculating from timestamps
    avg_resolution = ZendeskTicket
      .where.not(first_resolution_time_in_minutes: nil)
      .average(:first_resolution_time_in_minutes)

    if avg_resolution.nil?
      # Fallback to full_resolution_time_in_minutes
      avg_resolution = ZendeskTicket
        .where.not(full_resolution_time_in_minutes: nil)
        .average(:full_resolution_time_in_minutes)
    end

    if avg_resolution.nil?
      # Calculate from solved/closed tickets using updated_at as proxy for resolution time
      # Note: This is approximate since incremental API doesn't include metric fields
      solved_tickets = ZendeskTicket
        .where(status: ["solved", "closed"])
        .where.not(created_at: nil)
        .where.not(updated_at: nil)

      if solved_tickets.any?
        total_minutes = solved_tickets.sum do |ticket|
          # Use updated_at as proxy for when ticket was resolved
          # This is approximate but better than nothing
          resolution_time = ticket.updated_at
          created_time = ticket.created_at

          if resolution_time && created_time && resolution_time > created_time
            ((resolution_time - created_time) / 60).round
          else
            0
          end
        end
        avg_resolution = total_minutes.to_f / solved_tickets.count if total_minutes > 0 && solved_tickets.count > 0
      end
    end

    @avg_resolution_time = avg_resolution&.round(1)
    @has_resolution_data = !@avg_resolution_time.nil?

    @tickets_by_status = ZendeskTicket
      .where.not(status: nil)
      .group(:status)
      .count
  end
end
