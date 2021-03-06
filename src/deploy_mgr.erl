-module(deploy_mgr).
-behavior(gen_server).

% client API
-export([start_link/0, stop/0, deploy/1, deploy_async/1]).

% gen_server API
-export([init/1, handle_call/3, handle_cast/2,
         handle_info/2, terminate/2, code_change/3]).

-define(SERVER, ?MODULE).

start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

stop() ->
    gen_server:call(?MODULE, stop).

deploy(RepoData) ->
    gen_server:call(?MODULE, {deploy, RepoData}).

deploy_async(RepoData) ->
    gen_server:cast(?MODULE, {deploy, RepoData}).

init([]) ->
    lager:debug("deploy_mgr initialized", []),
    {ok, initialized}.

handle_call({deploy, RepoData}, _From, State) ->
    do_deploy({call, State}, RepoData);
handle_call(stop, _From, State) ->
    {stop, normal, stopped, State}.

handle_cast({deploy, RepoData}, State) ->
    do_deploy({cast, State}, RepoData).

handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

do_deploy({call, State}, RepoData) ->
    {ok, Reply} = deploy_it(RepoData),
    {reply, Reply, State};
do_deploy({cast, State}, RepoData) ->
    deploy_it(RepoData),
    {noreply, State}.

deploy_it({Ref, RepoName, RepoFullName, RepoCloneList}) ->
    % Process:
    % Update git
    % if ok, restart monit
    case config_util:git_config(Ref, RepoName, RepoFullName) of
        {ok, MonitName, GitConfig} ->
            lager:debug("monit name: ~p, git config ~p", [MonitName, GitConfig]),
            {ok, GitResult} = git_util:clone(RepoCloneList, GitConfig),
            {ok, MonitResult} = monit_util:service_action(restart, MonitName),
            {ok, [{git, GitResult}, {monit, MonitResult}]};
        {error, ErrMsg} ->
            lager:warning("Not deploying: ~s", [ErrMsg]),
            {ok, ErrMsg}
    end.
