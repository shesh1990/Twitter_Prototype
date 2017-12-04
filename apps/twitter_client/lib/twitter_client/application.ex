defmodule TwitterClient.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do

        # List all child processes to be supervised
        port = System.get_env("PORT")
        port= cond do
                  port == nil-> 4040
                          true->port|> String.trim |> String.to_integer
              end
        children = [
          {Task.Supervisor, name: TwitterClient.TaskSupervisor},
          Supervisor.child_spec({Task, fn -> TwitterClient.connectClient('127.0.0.1',port) end}, restart: :permanent)
        ]
    
        opts = [strategy: :one_for_one, name: TwitterClient.Supervisor]
        Supervisor.start_link(children, opts)

  end
end
