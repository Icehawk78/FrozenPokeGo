require 'poke-api'
require 'io/console'
require 'pp'

@levels = YAML.load(File.read('levels.yml'))
@evolutions = YAML.load(File.read('evolutions.yml'))
@pokemon_families = Hash[*@evolutions.map{|e| [e[:pokemon_id], e[:family_id]]}.flatten]
@pokemon_evolution_candies = Hash[*@evolutions.map{|e| [e[:pokemon_id], e[:candy]]}.flatten]

def set_stat_nicknames pokemon
  atk = pokemon[:individual_attack]
  dfs = pokemon[:individual_defense]
  sta = pokemon[:individual_stamina]
  @client.nickname_pokemon(pokemon_id: pokemon[:id], nickname: ("%02d: %d/%d/%d" % [atk+dfs+sta, atk, dfs, sta]))
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

unsafe.find_all{|pk| pk[:nickname] != 'X'}.each{|pk| @client.nickname_pokemon(pokemon_id: pk[:id], nickname: 'X')}
relevent.map{|k,v| v}.flatten.find_all{|pk| pk[:nickname].empty?}.each{|pk| set_stat_nicknames pk}
pp @client.call.response

r1 = Random.new
safe.each{|pk| 
  @client.release_pokemon(pokemon_id: pk[:id])
  pp @client.call.response
  sleep r1.rand(5.0..7.0)
}
