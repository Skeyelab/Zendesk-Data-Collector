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

    if avg_resolution
      total_minutes = avg_resolution.round
      hours = total_minutes / 60
      minutes = total_minutes % 60

      @avg_resolution_hours = hours
      @avg_resolution_minutes = minutes
      @avg_resolution_time_formatted = if hours > 0
        "#{hours}h #{minutes}m"
      else
        "#{minutes}m"
      end
    else
      @avg_resolution_hours = nil
      @avg_resolution_minutes = nil
      @avg_resolution_time_formatted = nil
    end

    @has_resolution_data = !@avg_resolution_time_formatted.nil?

    @tickets_by_status = ZendeskTicket
      .where.not(status: nil)
      .group(:status)
      .count

    @tickets_by_priority = ZendeskTicket
      .where.not(priority: nil)
      .group(:priority)
      .count

    # Tickets over time - group by date and format as date strings
    tickets_by_date = ZendeskTicket
      .where.not(created_at: nil)
      .group("DATE(created_at)")
      .order("DATE(created_at) ASC")
      .count

    # Format dates as YYYY-MM-DD strings for Chartkick
    @tickets_over_time = tickets_by_date.transform_keys { |date| date.strftime("%Y-%m-%d") }
  end
end
