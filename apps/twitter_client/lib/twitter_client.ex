defmodule TwitterClient do

  def connectClient(ip_address,port) do 
    Task.start(fn ->start_client(ip_address,port,1) end)
    keep_main_process_alive()
  end

  defp keep_main_process_alive() do
    Process.sleep 1000
    keep_main_process_alive()
  end

  defp start_client(ip_address,port,client_id) do
    Process.sleep 10
    cond do 
      client_id==20000->"Reached maximum user limit\r\n" 
      true-> {:ok, socket} = :gen_tcp.connect(ip_address, port,  [:binary, packet: :raw, active: false])
              Task.start(fn ->perform_client_operations(socket,client_id) end)
              Process.sleep 100
              start_client(ip_address,port,client_id+1)
    end
  end
  
  defp perform_client_operations(socket,client_id) do 
    send_and_recv(socket,'register #{client_id},password\r\n');
    send_and_recv(socket,'login #{client_id},password\r\n')
    Task.start(fn ->subscribe_user(socket,client_id,client_id-1) end)
    start_tweets(socket,client_id,1)
  end

  defp start_tweets(socket,client_id,tweet_count) do
    send_and_recv(socket,'tweet User Id: #{client_id}: Number of Tweets by current user:#{tweet_count}\r\n')
    Process.sleep client_id
    start_tweets(socket,client_id,tweet_count+1)
  end

  defp subscribe_user(socket,follower_id,user_to_follow) do
    cond do
      user_to_follow==0->"No user to subscribe"
      true->if rem(follower_id,user_to_follow)===0 do
               send_and_recv(socket,'subscribe #{user_to_follow}\r\n')
             end
             send_and_recv(socket,'retweet #{user_to_follow}\r\n')
             subscribe_user(socket,follower_id,user_to_follow-1)
    end

  end

  defp send_and_recv(socket, command) do
    :ok = :gen_tcp.send(socket, command)
    {:ok, data} = :gen_tcp.recv(socket, 0)
    IO.puts "#{data}"
  end
end
