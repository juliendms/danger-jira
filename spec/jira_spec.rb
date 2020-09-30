require File.expand_path("../spec_helper", __FILE__)

module Danger
  describe Danger::DangerJira do
    it "should be a plugin" do
      expect(Danger::DangerJira.new(nil)).to be_a Danger::Plugin
    end

    #
    # You should test your custom attributes and methods here
    #
    describe "with Dangerfile" do
      before do
        @header_response = { "Content-Type" => "application/json" }
        @jira = testing_dangerfile.jira
        DangerJira.send(:public, *DangerJira.private_instance_methods)
        github = Danger::RequestSources::GitHub.new({}, testing_env)
        ENV["DANGER_JIRA_URL"] = "https://myjira.atlassian.net"
      end

      it "can find jira issues via title" do
        allow(@jira).to receive_message_chain("github.pr_title").and_return("Ticket [WEB-123] and WEB-124")
        issues = @jira.find_jira_issues(key: "WEB")
        expect(issues).to eq(["WEB-123", "WEB-124"])
      end

      it "can find jira issues in commits" do
        single_commit = Object.new
        def single_commit.message
          "WIP [WEB-125]"
        end
        commits = [single_commit]
        allow(@jira).to receive_message_chain("git.commits").and_return(commits)
        issues = @jira.find_jira_issues(
          key: "WEB",
          search_title: false,
          search_commits: true
        )
        expect(issues).to eq(["WEB-125"])
      end

      it "can find jira issues in pr body" do
        allow(@jira).to receive_message_chain("github.pr_body").and_return("[WEB-126]")
        issues = @jira.find_jira_issues(
          key: "WEB",
          search_title: false,
          search_commits: false
        )
        expect(issues).to eq(["WEB-126"])
      end

      it "can find no-jira in pr body" do
        allow(@jira).to receive_message_chain("github.pr_body").and_return("[no-jira] Ticket doesn't need a jira but [WEB-123] WEB-123")
        result = @jira.should_skip_jira?(search_title: false)
        expect(result).to be(true)
      end

      it "can find no-jira in title" do
        allow(@jira).to receive_message_chain("github.pr_title").and_return("[no-jira] Ticket doesn't need jira but [WEB-123] and WEB-123")
        result = @jira.should_skip_jira?
        expect(result).to be(true)
      end

      it "can remove duplicates" do
        allow(@jira).to receive_message_chain("github.pr_title").and_return("Ticket [WEB-123] and WEB-123")
        issues = @jira.find_jira_issues(key: "WEB")
        expect(issues).to eq(["WEB-123"])
      end

      it "can retrieve the summary of an issue from a public JIRA" do
        issue = "WEB-200"
        summary = "Test public summary"
        expected_output = "<a href='#{ENV['DANGER_JIRA_URL']}/browse/#{issue}'>#{issue} - #{summary}</a>"
        json_return = "{\"key\":\"#{issue}\",\"fields\":{\"summary\":\"#{summary}\"}}"
        stub = stub_request(:get, "#{ENV['DANGER_JIRA_URL']}/rest/api/2/issue/#{issue}?fields=summary").to_return(body: json_return, headers: @header_response)
        result = @jira.link(issue: issue, include_summary: true)
        expect(stub).to have_been_requested
        expect(result).to eq(expected_output)
      end

      it "can retrieve the summary of an issue from a private JIRA" do
        ENV["DANGER_JIRA_API_TOKEN"] = "1234"
        issue = "WEB-201"
        summary = "Test private summary"
        expected_output = "<a href='#{ENV['DANGER_JIRA_URL']}/browse/#{issue}'>#{issue} - #{summary}</a>"
        json_return = "{\"key\":\"#{issue}\",\"fields\":{\"summary\":\"#{summary}\"}}"
        stub = stub_request(:get, "#{ENV['DANGER_JIRA_URL']}/rest/api/2/issue/#{issue}?fields=summary").
          with(headers: { "Authorization" => "Basic #{ENV['DANGER_JIRA_API_TOKEN']}" }).
          to_return(body: json_return, headers: @header_response)
        result = @jira.link(issue: issue, include_summary: true)
        expect(stub).to have_been_requested
        expect(result).to eq(expected_output)
      end

      it "can transition a set of issue" do
        issues = ["WEB-202", "WEB-203"]
        transition_id = 1
        expected_json = "{\"transition\":{\"id\":\"#{transition_id}\"}}"
        uri_template = Addressable::Template.new "#{ENV['DANGER_JIRA_URL']}/rest/api/2/issue/{issue}/transitions"
        stub = stub_request(:post, uri_template).
          with(body: expected_json, headers: { "Authorization" => "Basic #{ENV['DANGER_JIRA_API_TOKEN']}" })
        @jira.transition(jira_issues: issues, transition_id: transition_id)
        expect(stub).to have_been_requested.twice
      end
    end
  end
end
