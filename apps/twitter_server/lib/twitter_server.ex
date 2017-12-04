defmodule TwitterServer do
  require Logger
  alias TwitterServer.Database
  
    @doc """
    Starts accepting connections on the given `port`.
    """
    def accept(port) do
      ConCache.start_link([], name: :registered_user )
      ConCache.start_link([], name: :loggedin_user )
      ConCache.start_link([], name: :user_session)
      ConCache.start_link([], name: :tweets)
      ConCache.start_link([], name: :retweets)
      ConCache.start_link([ets_options: [:bag]], name: :followers)
      ConCache.start_link([ets_options: [:bag]], name: :following)
      ConCache.start_link([ets_options: [:bag]], name: :mentions)
      ConCache.start_link([ets_options: [:bag]], name: :tags)
      ConCache.start_link([ets_options: [:bag]], name: :userTweets)
      ConCache.start_link([], name: :last_keyids)
      ConCache.put(:last_keyids,:tweets,1)
      {:ok, socket} = :gen_tcp.listen(port,
                        [:binary, packet: :line, active: false, reuseaddr: true])
      Logger.info "Accepting connections on port #{port}"
      loop_acceptor(socket)
    end
  
    defp loop_acceptor(socket) do
      {:ok, client} = :gen_tcp.accept(socket)
      {:ok, pid} = Task.Supervisor.start_child(TwitterServer.TaskSupervisor, fn -> serve(client) end)
      :ok = :gen_tcp.controlling_process(client, pid)
      "Connection Successful\r\n" |> write_line(client)
      loop_acceptor(socket)
    end
  
    defp serve(socket) do  
      socket
      |> read_line()
      |> Database.read_request(socket)
      |> write_line(socket)
  
      serve(socket)
    end
  
    defp read_line(socket) do
      {:ok, data} = :gen_tcp.recv(socket, 0)
      String.replace(data,"\r\n","")
    end
  
    defp write_line(line, socket) do
      :gen_tcp.send(socket, line)
    end
end
