defmodule TwitterServer.Database do


    def read_request(request,client) do   
        request=String.trim(request, "\r\n")    
        query=Regex.split(~r{ }, request, [parts: 2])
        case query do
            [operation,values] ->  process_request(operation,values,client)
            [operation] -> process_request(operation,"",client)
            _ -> "Insufficient parameters. Please input correct number of parameters\r\n"
        end
    end

    defp process_request(operation,values,client) do
        case operation do
            "register" -> values |> process_registration 
            "login" ->    process_login(client,values)
            _  ->logged_in=check_user_session(client)
                 case logged_in do
                    "false"->"Invalid session. Please login\r\n"
                    _-> case operation do
                            "fetchusers"-> users= :registered_user|> get_keys |> Enum.join(",")
                                           "#{users}\r\n"
                            "fetchmention"->mentions=values |> fetch_mention |> Enum.join("\r\n\n")
                                           "#{mentions}\r\n"
                            "fetchtag"->tags=values |> fetch_tags |> Enum.join("\r\n\n")
                                       "#{tags}\r\n"
                            "subscribe"-> subscribe(client,values)
                            "tweet"-> tweet(client,values)
                            "retweet"-> retweet(client,values)
                            "logout"->logout(client)
                            "fetchtweets"->fetch_tweets(client) |> Enum.join("\r\n\n")
                            _ -> 
                                "Invalid operations #{operation}\r\n"
                    end
                 end
        end
    end

    defp process_registration(values) do
        args=Regex.split(~r{,}, values, [parts: 2])
        case args do
            [username,password]->
                result=ConCache.insert_new(:registered_user,String.to_atom(username),password)
                
                case result  do
                    {:error, :already_exists}->"User already exist.Please try login/ or use different user id to register\r\n" 
                    _-> "Registration successful. Please try login\r\n"
                end
                                    
            _ -> "Registration unsuccessful. Invalid arguments\r\n"
        end
    end

    defp process_login(client,values) do
        args=Regex.split(~r{,}, values, [parts: 3])
        case args do

            [username,password]->
                user_details=ConCache.get(:registered_user,String.to_atom(username))  
                case user_details  do
                    nil->"User not registered.\r\n"
                    pass-> if pass===password do
                              is_logged_in=ConCache.get(:loggedin_user,String.to_atom(username)) 
                              case is_logged_in do
                                nil->
                                     client_atom=client |> Kernel.inspect |> String.to_atom
                                     username_atom=String.to_atom(username)
                                     ConCache.put(:loggedin_user,username_atom,client) 
                                     ConCache.put(:user_session,client_atom,username)        
                                     "Login successful\r\n"
                                _->" User already logged in. Use force with to login\r\n "
                              end
                            else
                                "Incorrect password. Try again\r\n"
                            end
                end

            [username,password,force]->  
                            if force === "force" do
                                        user_details=ConCache.get(:registered_user,String.to_atom(username))  
                                        case user_details  do
                                            nil->"User not registered.\r\n"
                                            pass-> if pass===password do
                                                        old_client=ConCache.get(:loggedin_user,String.to_atom(username))
                                                        ConCache.delete(:user_session,old_client)
                                                        ConCache.put(:loggedin_user,String.to_atom(username),client) 
                                                        ConCache.put(:user_session,String.to_atom(inspect(client)),username);
                                                        "Login successful\r\n"                                 
                                                    else
                                                        "Incorrect password. Try again\r\n"
                                                    end
                                        end  
                            else  
                                "Invalid option. Use force to force login\r\n"
                            end                
            _ -> "Login unsuccessful. Invalid arguments\r\n"
        end
    end
    defp logout(client) do
        username=ConCache.get(:user_session,String.to_atom(inspect(client)))
        ConCache.delete(:user_session,String.to_atom(inspect(client)))
        ConCache.delete(:loggedin_user,String.to_atom(username))
        "Logout Successful \r\n"
    end
    defp check_user_session(client) do
        current_user= ConCache.get(:user_session,String.to_atom(inspect(client)))
        case current_user do
           nil-> "false"
           _->true
        end
    end
    defp subscribe(client,values) do
      case  ConCache.get(:registered_user,String.to_atom(values)) do
          nil-> "User does not exist. Subscription unsuccessful\r\n"
          _-> current_user= ConCache.get(:user_session,String.to_atom(inspect(client)))
              if values===current_user do
                "Cannot subscribe to yourself\r\n"
              else
                ConCache.put(:followers,String.to_atom(values),current_user)
                ConCache.put(:following,String.to_atom(current_user),String.to_atom(values))
                "Subscribed to #{values}\r\n"
              end
      end      
    end
    defp fetch_tweets(client) do
        current_user= ConCache.get(:user_session,String.to_atom(inspect(client)))
        following_users=ConCache.get(:following,String.to_atom(current_user))
        cond do 
         following_users==nil->["You are not following anyone. Please follow to get tweets\r\n"]
         true->IO.inspect following_users
            fetch_users_tweet(following_users,[])
        end
    end
    defp tweet(client,values) do
        mentions=extract_mentions(values)
        valid=
        case mentions do
            []->"true"
            _->check_valid_user(mentions)
        end
        case valid do
            "false"->"Invalid mention. User does not exist. Tweet Failed\r\n"
             _->    current_user= ConCache.get(:user_session,String.to_atom(inspect(client)))
             last_tweetid= ConCache.isolated(:last_keyids,:tweets, fn() ->
                 fetch_tweet_id()   
              end)
                   # last_tweetid= ConCache.get(:last_keyids,:tweets)
                    #ConCache.put(:last_keyids,:tweets,last_tweetid+1)  
                    IO.puts "Total Tweet: #{last_tweetid}     TweetBy : #{current_user}"
                    ConCache.insert_new(:tweets,last_tweetid|> Integer.to_string|> String.to_atom, [values,current_user] )
                    ConCache.put(:userTweets,String.to_atom(current_user),last_tweetid|> Integer.to_string|> String.to_atom)  
                    followers=ConCache.get(:followers,String.to_atom(current_user))
                    followers=
                        cond do
                            followers==nil->[]
                            is_list(followers)->followers
                            true->List.insert_at([],0,followers)
                        end
                    tags=extract_tags(values)
                    Task.start(fn ->store_tags(tags,last_tweetid) end)
                    Task.start(fn -> store_mentions(mentions,last_tweetid) end)
                    followers=
                    case mentions do
                        nil->followers
                        _-> Enum.each(mentions, fn(user)->send_tweets(user,"You were mentioned in New tweet from (Tweet Id: #{last_tweetid}) #{current_user}\r\n #{values}\r\n") end)
                            case followers do 
                                nil->[]
                                _  ->followers -- mentions
                            end
                    end
                       
                    case followers do
                        nil-> "No followers\r\n"
                        _-> Task.start(fn ->send_tweets(followers,"New tweet from (Tweet Id: #{last_tweetid}) #{current_user}\r\n #{values}\r\n") end)
                    end                  
                    "You tweeted (Tweet Id: #{last_tweetid})\r\n #{values}\r\n"  
                end
    end

    defp fetch_tweet_id() do
        key_id=ConCache.get(:last_keyids,:tweets)
        ConCache.put(:last_keyids,:tweets,key_id+1) 
        key_id
    end

    defp check_valid_user([head|tail]) do
       case ConCache.get(:registered_user,String.to_atom(head)) do
        nil->"false"
        _->check_valid_user(tail)
       end
    end
    defp check_valid_user([]) do
        "true"
     end
    defp retweet(client,values) do
        current_user= ConCache.get(:user_session,String.to_atom(inspect(client)))
        case current_user do
           nil-> "Invalid session. Please start new session\r\n"
            _ ->last_retweetid=case ConCache.get(:last_keyids,:retweets) do
                                nil->1
                                x-> x+1
                             end
                current_user= ConCache.get(:user_session,String.to_atom(inspect(client)))  
                [tweet,original_user]= ConCache.get(:tweets,values|> String.to_atom)
                ConCache.insert_new(:retweets,last_retweetid|> Integer.to_string|> String.to_atom, [values,current_user] )
                ConCache.put(:last_keyids,:retweets,last_retweetid)   
                followers=ConCache.get(:followers,String.to_atom(current_user))
                case followers do
                    nil-> "No followers\r\n"
                    _-> Task.start(fn ->send_tweets(followers,"Retweet from (Tweet Id: #{values}) #{current_user}\r\n #{tweet}\r\n") end)
                end          
               
                "You Retweeted (Tweet Id: #{values})\r\n #{tweet}\r\n"
        end
    end

    defp send_tweets([],tweet_msg) do
    end

    defp send_tweets([head|tail],tweet_msg)  do
        client= ConCache.get(:loggedin_user,String.to_atom(head))
        case client do
            nil->"User not logged in\r\n"
            _-> :gen_tcp.send(client, tweet_msg)
                 send_tweets(tail,tweet_msg)
        end
    end
    
    defp send_tweets(user,tweet_msg)  do
        client= ConCache.get(:loggedin_user,String.to_atom(user))
        case client do
            []->"User not logged in\r\n"
            _-> :gen_tcp.send(client, tweet_msg)
        end
    end

    defp fetch_mention(username) do
        tweet=ConCache.get(:mentions,String.to_atom(username))
       cond do
        tweet==nil->["Sorry. No mentions for the user\r\n"]
        is_list(tweet)-> fetch_tweet(tweet,[])
        true->fetch_tweet(tweet,[])
       end
    end 
    defp fetch_tags(tag_val) do
        tweet=ConCache.get(:tags,String.to_atom(tag_val))
       cond do
        tweet==nil->["Sorry. No tags for the topic\r\n"]
        is_list(tweet)-> fetch_tweet(tweet,[])
        true->fetch_tweet(tweet,[])
       end
    end 

    defp fetch_tweet([head|tail],acc) do
        [values,current_user]= ConCache.get(:tweets,String.to_atom("#{head}"))
        fetch_tweet(tail, acc ++ [values]) 
    end

    defp fetch_tweet(tweet_id,acc) do
        case tweet_id do
            []-> acc
            _->[values,current_user]= ConCache.get(:tweets,String.to_atom("#{tweet_id}"))
              acc ++ [values]
        end       
    end


    defp fetch_user_tweet(user_name) do
        tweet_ids=ConCache.get(:userTweets,user_name)
        cond do
         tweet_ids==nil->[]
         is_list(tweet_ids)-> fetch_tweet(tweet_ids,[])
         true->fetch_tweet(tweet_ids,[])
        end
    end

    defp fetch_users_tweet([head|tail],acc) do
        fetch_users_tweet(tail, acc ++ fetch_user_tweet(head)) 
    end

    defp fetch_users_tweet(user_name,acc) do
        case user_name do
            []-> acc
            nil->acc
            _-> acc ++ fetch_user_tweet(user_name)
             
        end       
    end

    defp get_keys(table) do
        table
        |> ConCache.ets
        |> :ets.tab2list
        |>Enum.reduce([], fn ({key, _}, acc) -> List.insert_at(acc,0,key) end)
    end
    defp extract_tags(text) do
        Regex.scan(~r/\S*#(?<tag>:\[[^\]]|[a-zA-Z0-9]+)/, text, capture: :all_names) |> List.flatten
    end
    defp extract_mentions(text) do
        Regex.scan(~r/\S*@(?<tag>:\[[^\]]|[a-zA-Z0-9]+)/, text, capture: :all_names) |> List.flatten
    end
    defp store_tags([head|tail],tweet_id) do   
        ConCache.put(:tags,String.to_atom(head),tweet_id)
        store_tags(tail,tweet_id)
    end
    defp store_tags(empty,tweet_id) do    
    end

    defp store_mentions([head|tail],tweet_id) do     
        ConCache.put(:mentions,String.to_atom(head),tweet_id)
        store_mentions(tail,tweet_id)
    end
    defp store_mentions(empty,tweet_id) do      
        
    end
  end
  