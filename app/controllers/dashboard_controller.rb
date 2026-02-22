class DashboardController < ApplicationController
  before_action :authenticate_admin_user!

  def index
    @total_tickets = ZendeskTicket.count
    @active_desks = Desk.where(active: true).count

    # Open/pending workload
    @open_tickets = ZendeskTicket.where(status: %w[new open pending]).count
    @solved_last_7_days = ZendeskTicket.where(status: %w[solved closed])
      .where(solved_at: 7.days.ago..)
      .count
    @solved_last_30_days = ZendeskTicket.where(status: %w[solved closed])
      .where(solved_at: 30.days.ago..)
      .count

    # Average resolution time
    avg_resolution = ZendeskTicket
      .where.not(first_resolution_time_in_minutes: nil)
      .average(:first_resolution_time_in_minutes)

    avg_resolution ||= ZendeskTicket
      .where.not(full_resolution_time_in_minutes: nil)
      .average(:full_resolution_time_in_minutes)

    if avg_resolution.nil?
      solved_tickets = ZendeskTicket
        .where(status: %w[solved closed])
        .where.not(created_at: nil)
        .where.not(updated_at: nil)

      if solved_tickets.any?
        total_minutes = solved_tickets.sum do |ticket|
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
      @avg_resolution_time_formatted = hours > 0 ? "#{hours}h #{minutes}m" : "#{minutes}m"
    else
      @avg_resolution_hours = nil
      @avg_resolution_minutes = nil
      @avg_resolution_time_formatted = nil
    end

    @has_resolution_data = !@avg_resolution_time_formatted.nil?

    # Average first reply time
    avg_first_reply = ZendeskTicket
      .where.not(first_reply_time_in_minutes: nil)
      .average(:first_reply_time_in_minutes)

    if avg_first_reply
      total_minutes = avg_first_reply.round
      hours = total_minutes / 60
      minutes = total_minutes % 60
      @avg_first_reply_formatted = hours > 0 ? "#{hours}h #{minutes}m" : "#{minutes}m"
    end

    @tickets_by_status = ZendeskTicket
      .where.not(status: nil)
      .group(:status)
      .count

    @tickets_by_priority = ZendeskTicket
      .where.not(priority: nil)
      .group(:priority)
      .count

    @tickets_by_channel = ZendeskTicket
      .where.not(via: [nil, ""])
      .group(:via)
      .count

    @tickets_by_group = ZendeskTicket
      .where.not(group_name: [nil, ""])
      .group(:group_name)
      .count

    @top_assignees = ZendeskTicket
      .where.not(assignee_name: [nil, ""])
      .group(:assignee_name)
      .count
      .sort_by { |_name, count| -count }
      .first(10)
      .to_h

    @satisfaction_scores = ZendeskTicket
      .where.not(satisfaction_score: [nil, ""])
      .where.not(satisfaction_score: "unoffered")
      .group(:satisfaction_score)
      .count

    # Tickets over time - group by date and format as date strings
    tickets_by_date = ZendeskTicket
      .where.not(created_at: nil)
      .group("DATE(created_at)")
      .order("DATE(created_at) ASC")
      .count

    @tickets_over_time = tickets_by_date.transform_keys { |date| date.strftime("%Y-%m-%d") }
  end
end
