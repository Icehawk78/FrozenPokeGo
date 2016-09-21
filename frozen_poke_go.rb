require 'poke-api'
require 'io/console'
require 'pp'

Poke::API::Logging.log_level = :WARN

@levels = YAML.load(File.read('levels.yml'))
@evolutions = YAML.load(File.read('evolutions.yml'))
@pokemon_families = Hash[*@evolutions.map{|e| [e[:pokemon_id], e[:family_id]]}.flatten]
@pokemon_evolution_candies = Hash[*@evolutions.map{|e| [e[:pokemon_id], e[:candy]]}.flatten]

def set_stat_nickname pokemon
  atk = pokemon[:individual_attack]
  dfs = pokemon[:individual_defense]
  sta = pokemon[:individual_stamina]
  nickname = ("%02d: %d/%d/%d" % [atk+dfs+sta, atk, dfs, sta])
  @client.nickname_pokemon(pokemon_id: pokemon[:id], nickname: nickname)
  nickname
end

def get_level pokemon
  @levels.find_index(pokemon[:cp_multiplier].round(8)) + pokemon[:num_upgrades]
end

def evolutions_possible candy_count, candy_needed, transfer_finished=false
  evolves = candy_count / candy_needed
  until ((candy_count + (transfer_finished ? 2 : 1) * evolves) - (evolves * candy_needed)) < candy_needed
    evolves += ((candy_count + (transfer_finished ? 2 : 1) * evolves) - (evolves * candy_needed)) / candy_needed
  end
  evolves
end

@method = 'google'

# Wrapped for safety when pasted into IRB, remove when run externally
1.times do
  print 'Google Email: '
  @username = gets.chomp
  print "Password for #@username: "
  @password = STDIN.noecho(&:gets).chomp
  puts ''
end

@client = Poke::API::Client.new
@client.login(@username, @password, @method)

@client.get_inventory

response = @client.call.response
inventory = response[:GET_INVENTORY][:inventory_delta][:inventory_items].map{|x| x[:inventory_item_data]}

candy = inventory.map{|x| x[:pokemon_family]}.compact
family_candy = Hash[*candy.map{|c| [c[:family_id], c[:candy]]}.flatten]
pokemon = inventory.map{|x| x[:pokemon_data] if (x[:pokemon_data] and not x[:pokemon_data][:is_egg])}.compact

poke_groups = pokemon.group_by{|pk| pk[:pokemon_id]}
family_groups = pokemon.group_by{|pk| @pokemon_families[pk[:pokemon_id]]}
pokemon_counts = Hash[*poke_groups.map{|type, pk_list| [type, pk_list.size]}.flatten]

irrelevent = family_groups.map{|family_type, family_list|
  family_list.find_all{|p1|
    family_list.any?  {|p2|
      p1[:id] != p2[:id] and 
        get_level(p1) <= get_level(p2) and 
        p1[:individual_attack] <= p2[:individual_attack] and 
        p1[:individual_defense] <= p2[:individual_defense] and 
        p1[:individual_stamina] <= p2[:individual_stamina] 
    }
  }
}.flatten
relevent = (pokemon - irrelevent).group_by{|pk| pk[:pokemon_id]}

unsafe = irrelevent.group_by{|x| x[:pokemon_id]}.find_all{|id, all_pk|
  pokemon_counts[id] == all_pk.size or
  (!@pokemon_evolution_candies[id].nil? and evolutions_possible(family_candy[@pokemon_families[id]] + all_pk.size, @pokemon_evolution_candies[id], true) >= relevent[id].size)
}.map(&:last).flatten
safe = (irrelevent - unsafe)

poke_groups.each{|species, pk_list|
  family  = @pokemon_families[species]
  unless family_candy[family].nil? or @pokemon_evolution_candies[species].nil?
    release_unsafe_list = []
    evo_able = evolutions_possible(family_candy[family], @pokemon_evolution_candies[species], true)
	safe_count = safe.find_all{|pk| pk[:pokemon_id] == species}.size
	if (evo_able < pk_list.size and evo_able > safe_count)
	  drop_count = pk_list.size - evo_able
	  release_unsafe_list = unsafe.find_all{|pk| pk[:pokemon_id] == species}.sample(drop_count)
	end
    puts "#{species}: #{evo_able}/#{pk_list.size} [unsafe release count: #{release_unsafe_list.size}]"
	safe += release_unsafe_list
  end
}

relevent_unnamed = relevent.map{|k,v| v}.flatten.find_all{|pk| pk[:nickname].empty?}
unsafe_unnamed = unsafe.find_all{|pk| pk[:nickname] != 'X'}
unsafe_unnamed.each{|pk| @client.nickname_pokemon(pokemon_id: pk[:id], nickname: 'X')}
relevent_unnamed.each{|pk| puts "Adding nickname of #{set_stat_nickname(pk)} to CP #{pk[:cp]} #{pk[:pokemon_id]}"}
puts "Marking unsafe: #{unsafe_unnamed.group_by{|pk| pk[:pokemon_id]}.map{|k,v| "#{v.size} #{k}"} * ', '}"
#pp @client.call.response

puts "Releasing #{safe.size} safe pokemon: #{safe.group_by{|pk| pk[:pokemon_id]}.map{|k,v| "#{v.size} #{k}"} * ', '}"
r1 = Random.new
safe.each{|pk|
  puts "Releasing #{pk[:pokemon_id]}..."
  sleep r1.rand(5.0..7.0)
  @client.release_pokemon(pokemon_id: pk[:id])
  @client.call
}
