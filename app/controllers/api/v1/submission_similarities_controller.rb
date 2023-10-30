# frozen_string_literal: true

require 'api_keys_handler'

module Api
  module V1
    # The `SubmissionSimilaritiesController` is responsible for handling API requests related to
    # fetching submission similarities for assignments. It provides an endpoint for clients to
    # retrieve submission similarities associated with a given assignment. The API key must be
    # provided and validated for access, and the user associated with the API key must have
    # authorization for the specified course.
    class SubmissionSimilaritiesController < ApplicationController
      skip_before_action :authenticate_user!

      before_action do |_controller|
        set_api_key_and_assignment
      end

      def index
        APIKeysHandler.authenticate_api_key
        render_submission_similarities
      rescue APIKeysHandler::APIKeyError => e
        render json: { error: e.message }, status: e.status
      end

      def show
        APIKeysHandler.authenticate_api_key
        render_pair_of_flagged_submissions
      rescue APIKeysHandler::APIKeyError => e
        render json: { error: e.message }, status: e.status
      end

      private

      def set_api_key_and_assignment
        set_api_key
        set_course_and_assignment
      end

      def set_api_key
        api_key_value = request.headers['X-API-KEY']
        APIKeysHandler.api_key = ApiKey.find_by(value: api_key_value)
      end

      def set_course_and_assignment(assignment_id = params[:assignment_id])
        assignment = Assignment.find_by(id: assignment_id)
        return nil if assignment.nil?

        APIKeysHandler.course = assignment.course
        assignment
      end

      def render_submission_similarities
        assignment = set_course_and_assignment(params[:assignment_id])

        if assignment.nil?
          render json: { error: 'Assignment does not exist' }, status: :bad_request
          return
        end
        # Check if the assignment has associated submission files.
        if assignment.submissions.empty?
          render json: { status: 'empty' }, status: :ok
          return
        end

        # Determine process status of assignment
        submission_similarity_process = assignment.submission_similarity_process
        case submission_similarity_process.status
        when SubmissionSimilarityProcess::STATUS_RUNNING, SubmissionSimilarityProcess::STATUS_WAITING
          render json: { status: 'processing' }, status: :ok
          return
        when SubmissionSimilarityProcess::STATUS_ERRONEOUS
          render json: { status: 'error', message: 'SSID is busy or under maintenance. Please try again later.' },
                 status: :service_unavailable
          return
        end

        submission_similarities = assignment.submission_similarities

        ### Filtering Code
        # Apply the threshold filter
        if params[:threshold].present?
          threshold_value = params[:threshold].to_f
          submission_similarities = submission_similarities.where('similarity >= ?', threshold_value)
        end

        # Apply the limit filter
        if params[:limit].present?
          limit_value = params[:limit].to_i
          submission_similarities = submission_similarities.limit(limit_value)
        end

        # Set the default per page value to 20
        per_page = 20

        # Sort the submission_similarities by similarity in descending order by default
        submission_similarities = submission_similarities.order(similarity: :desc)

        # Check if the page parameter is present and is a positive integer
        if params[:page].present? && params[:page].to_i.positive?
          page_number = params[:page].to_i
        else
          # If the page parameter is not present or not a positive integer, default to page 1
          page_number = 1
        end

        # Calculate the offset based on the page number
        offset_value = (page_number - 1) * per_page
        submission_similarities = submission_similarities.offset(offset_value).limit(per_page)


        render json: { status: 'processed', submissionSimilarities: submission_similarities }, status: :ok
      end

      def render_pair_of_flagged_submissions
        submission_similarity = SubmissionSimilarity.find_by(
          assignment_id: params[:assignment_id],
          id: params[:id]
        )

        if submission_similarity.nil?
          render json: { error: 'Submission similarities requested do not exist.' }, status: :bad_request
          return
        end

        max_similarity_percentage = submission_similarity.similarity
        matches = []

        submission_similarity.similarity_mappings.each do |similarity|
          matches.append(
            {
              student1: similarity.line_range1_string,
              student2: similarity.line_range2_string,
              statementCount: similarity.statement_count
            }
          )
        end

        render json: {
          maxSimilarityPercentage: max_similarity_percentage,
          matches: matches
        }, status: :ok
      end
    end
  end
end
