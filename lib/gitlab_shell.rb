require 'open3'
require 'shellwords'

require_relative 'gitlab_net'

class GitlabShell
  attr_accessor :key_id, :repo_name, :git_cmd, :repos_path, :repo_name, :git_annex_cmd, :git_annex_args

  def initialize
    @key_id = /key-[0-9]+/.match(ARGV.join).to_s
    @origin_cmd = ENV['SSH_ORIGINAL_COMMAND']
    @config = GitlabConfig.new
    @repos_path = @config.repos_path
    @user_tried = false
  end

  def exec
    if @origin_cmd
      parse_cmd

      if git_cmds.include?(@git_cmd)
        ENV['GL_ID'] = @key_id

        if validate_access
          process_cmd
        else
          message = "gitlab-shell: Access denied for git command <#{@origin_cmd}> by #{log_username}."
          $logger.warn message
          $stderr.puts "Access denied."
        end
      elsif @git_cmd == "git-annex-shell"
        if write_access
          process_annex_cmd(false)
        elsif read_access
          process_annex_cmd(true)
        else
          message = "gitlab-shell: Access denied for git annex command <#{@origin_cmd}> by #{log_username}."
          $logger.warn message
          $stderr.puts "Access denied."
        end
      else
        message = "gitlab-shell: Attempt to execute disallowed command <#{@origin_cmd}> by #{log_username}."
        $logger.warn message
        puts 'Not allowed command'
      end
    else
      puts "Welcome to GitLab, #{username}!"
    end
  end

  protected

  def parse_cmd
    args = Shellwords.shellwords(@origin_cmd)
    @git_cmd = args[0]
    if @git_cmd == "git-annex-shell"
      @git_annex_cmd = args[1]
      #remove leading ~/
      @repo_name = args[2].gsub(/~\//,"")
      @git_annex_args = args[3..-1]
    else
      @repo_name = args[1]
    end
  end

  def git_cmds
    %w(git-upload-pack git-receive-pack git-upload-archive)
  end

  def process_cmd
    repo_full_path = File.join(repos_path, repo_name)
    $logger.info "gitlab-shell: executing git command <#{@git_cmd} #{repo_full_path}> for #{log_username}."
    exec_cmd(@git_cmd,repo_full_path)
  end

  def process_annex_cmd(read_only)
    # git-annex restrict itself to read_only command
    if read_only
        ENV['GIT_ANNEX_SHELL_READONLY'] = '1'
    end
    # limit git-annex-shell to safe command
    ENV['GIT_ANNEX_SHELL_LIMITED'] = '1'
    repo_full_path = File.join(repos_path, repo_name)
    ENV['GIT_ANNEX_SHELL_DIRECTORY'] = repo_full_path

    $logger.info "gitlab-shell: executing git annex command <#{@git_cmd} #{@git_annex_cmd} #{repo_full_path} #{@git_annex_args.join(" ")}> for #{log_username} and (read_only=#{read_only})."
    exec_annex_cmd(@git_annex_cmd,repo_full_path,@git_annex_args)
  end

  def validate_access
    api.allowed?(@git_cmd, @repo_name, @key_id, '_any')
  end

  def read_access
    api.allowed?("git-receive-pack", @repo_name, @key_id, '_any')
  end

  def write_access
    api.allowed?("git-upload-pack", @repo_name, @key_id, '_any')
  end

  def exec_cmd *args
    Kernel::exec *args
  end

  def exec_annex_cmd(cmd,repo,args)
    Kernel::exec("git-annex-shell",cmd,repo,*args)
  end

  def api
    GitlabNet.new
  end

  def user
    # Can't use "@user ||=" because that will keep hitting the API when @user is really nil!
    if @user_tried
      @user
    else
      @user_tried = true
      @user = api.discover(@key_id)
    end
  end

  def username
    user && user['name'] || 'Anonymous'
  end

  # User identifier to be used in log messages.
  def log_username
    @config.audit_usernames ? username : "user with key #{@key_id}"
  end
end
