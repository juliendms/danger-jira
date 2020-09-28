require "httparty"
require "json"

module Danger
  # Links JIRA issues to a pull request.
  #
  # @example Check PR for the following JIRA project keys and links them
  #
  #          jira.check(key: "KEY", url: "https://myjira.atlassian.net/browse")
  #
  # @see  RestlessThinker/danger-jira
  # @tags jira
  #
  class DangerJira < Plugin
    # Checks PR for JIRA keys and links them
    #
    # @param [Array] key
    #         An array of JIRA project keys KEY-123, JIRA-125 etc.
    #
    # @param [String] emoji
    #         The emoji you want to display in the message.
    #
    # @param [Boolean] search_title
    #         Option to search JIRA issues from PR title
    #
    # @param [Boolean] search_commits
    #         Option to search JIRA issues from commit messages
    #
    # @param [Boolean] fail_on_warning
    #         Option to fail danger if no JIRA issue found
    #
    # @param [Boolean] report_missing
    #         Option to report if no JIRA issue was found
    #
    # @param [Boolean] skippable
    #         Option to skip the report if 'no-jira' is provided on the PR title, description or commits
    #
    # @param [Boolean] include_summary
    #         Option to retrieve the summary of the issue. May required DANGER_JIRA_API_TOKEN environment variable
    #
    # @return [void]
    #
    def check(key: nil, emoji: ":link:", search_title: true, search_commits: false, fail_on_warning: false, report_missing: true, skippable: true, include_summary: false)
      throw Error("'key' missing - must supply JIRA issue key") if key.nil?
      throw Error("The environment variable 'DANGER_JIRA_URL' is not set - must supply JIRA url") if ENV["DANGER_JIRA_URL"].nil?

      return if skippable && should_skip_jira?(search_title: search_title)

      jira_issues = find_jira_issues(
        key: key,
        search_title: search_title,
        search_commits: search_commits
      )

      if !jira_issues.empty?
        jira_urls = jira_issues.map { |issue| link(href: ensure_url_ends_with_slash(ENV["DANGER_JIRA_URL"]), issue: issue, include_summary: include_summary) }.join(", ")
        message("#{emoji} #{jira_urls}")
      elsif report_missing
        msg = "This PR does not contain any JIRA issue keys in the PR title or commit messages (e.g. KEY-123)"
        if fail_on_warning
          fail(msg)
        else
          warn(msg)
        end
      end
    end

    private

    def vcs_host
      return gitlab if defined? @dangerfile.gitlab
      return github
    end

    def find_jira_issues(key: nil, search_title: true, search_commits: false)
      # Support multiple JIRA projects
      keys = key.kind_of?(Array) ? key.join("|") : key
      jira_key_regex_string = "((?:#{keys})-[0-9]+)"
      regexp = Regexp.new(/#{jira_key_regex_string}/)

      jira_issues = []

      if search_title
        vcs_host.pr_title.gsub(regexp) do |match|
          jira_issues << match
        end
      end

      if search_commits
        git.commits.map do |commit|
          commit.message.gsub(regexp) do |match|
            jira_issues << match
          end
        end
      end

      if jira_issues.empty?
        vcs_host.pr_body.gsub(regexp) do |match|
          jira_issues << match
        end
      end
      return jira_issues.uniq
    end

    def should_skip_jira?(search_title: true)
      # Consider first occurrence of 'no-jira'
      regexp = Regexp.new("no-jira", true)

      if search_title
        vcs_host.pr_title.gsub(regexp) do |match|
          return true unless match.empty?
        end
      end

      vcs_host.pr_body.gsub(regexp) do |match|
        return true unless match.empty?
      end

      return false
    end

    def ensure_url_ends_with_slash(url)
      return "#{url}/" unless url.end_with?("/")
      return url
    end

    def link(href: nil, issue: nil, include_summary: false)
      if include_summary
        api_endpoint = href + "rest/api/2/issue/#{issue}?fields=summary"
        headers = nil

        unless ENV["DANGER_JIRA_API_TOKEN"].nil?
          headers = {
            Authorization: "Basic #{ENV['DANGER_JIRA_API_TOKEN']}"
          }
        end

        response = HTTParty.get(api_endpoint, headers)

        if response.code == 200
          summary = JSON.parse(response.body).dig("fields", "summary")
          return "<a href='#{href}browse/#{issue}'>#{issue} - #{summary}</a>"
        else
          message("Danger could not retrieve the summary of the issue #{issue}, check DANGER_JIRA_API_TOKEN and DANGER_JIRA_URL environment variables. Error code: #{response.code}.")
        end
      end

      return "<a href='#{href}browse/#{issue}'>#{issue}</a>"
    end
  end
end
