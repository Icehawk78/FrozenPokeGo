require 'poke-api'
require 'io/console'
require 'pp'

Poke::API::Logging.log_level = :WARN

@levels = YAML.load(File.read('levels.yml'))
@evolutions = YAML.load(File.read('evolutions.yml'))
@pokemon_families = Hash[*@evolutions.map { |e| [e[:pokemon_id], e[:family_id]] }.flatten]
@pokemon_evolution_candies = Hash[*@evolutions.map { |e| [e[:pokemon_id], e[:candy]] }.flatten]
@evolve_candy = 1
@release_candy = 2

@evolution_whitelist = [
    :BULBASAUR,
    :IVYSAUR,
    :CHARMANDER,
    :CHARMELEON,
    # :SQUIRTLE,
    :WARTORTLE,
    :CATERPIE,
    # :METAPOD,
    :WEEDLE,
    # :KAKUNA,
    :PIDGEY,
    # :PIDGEOTTO,
    :RATTATA,
    :SPEAROW,
    :EKANS,
    :PIKACHU,
    :SANDSHREW,
    # :NIDORAN_FEMALE,
    :NIDORINA,
    # :NIDORAN_MALE,
    :NIDORINO,
    :CLEFAIRY,
    :VULPIX,
    :JIGGLYPUFF,
    :ZUBAT,
    # :ODDISH,
    :GLOOM,
    :PARAS,
    :VENONAT,
    :DIGLETT,
    :MEOWTH,
    :PSYDUCK,
    :MANKEY,
    :GROWLITHE,
    # :POLIWAG,
    :POLIWHIRL,
    :ABRA,
    :KADABRA,
    :MACHOP,
    :MACHOKE,
    # :BELLSPROUT,
    :WEEPINBELL,
    :TENTACOOL,
    :GEODUDE,
    :GRAVELER,
    :PONYTA,
    :SLOWPOKE,
    :MAGNEMITE,
    :DODUO,
    :SEEL,
    :GRIMER,
    :SHELLDER,
    :GASTLY,
    # :HAUNTER,
    :DROWZEE,
    :KRABBY,
    :VOLTORB,
    :EXEGGCUTE,
    :CUBONE,
    :KOFFING,
    :RHYHORN,
    :TANGELA,
    :HORSEA,
    :SEADRA,
    :GOLDEEN,
    :STARYU,
    :MAGIKARP,
    # :EEVEE,
    :OMANYTE,
    :KABUTO
    # :DRATINI,
    # :DRAGONAIR
]

def set_stat_nickname pokemon
  atk = pokemon[:individual_attack]
  dfs = pokemon[:individual_defense]
  sta = pokemon[:individual_stamina]
  nickname = ("%02d: %d/%d/%d" % [atk+dfs+sta, atk, dfs, sta])
  @client.nickname_pokemon(pokemon_id: pokemon[:id], nickname: nickname)
  nickname
end

def get_stat_total pokemon
  pokemon[:individual_attack] + pokemon[:individual_defense] + pokemon[:individual_stamina]
end

def get_level pokemon
  @levels.find_index(pokemon[:cp_multiplier].round(8)) + pokemon[:num_upgrades]
end

def find_best pokemon_list, amount
  pokemon_list.sort_by { |p| -1 * (get_stat_total(p) + get_level(p)) }[0...amount]
end

def evolutions_possible candy_count, candy_needed, transfer_finished=false
  evolves = 0
  unless candy_count.nil? or candy_needed.nil?
    evolves = candy_count / candy_needed
    until ((candy_count + (@evolve_candy + (transfer_finished ? @release_candy : 0)) * evolves) - (evolves * candy_needed)) < candy_needed
      evolves += ((candy_count + (@evolve_candy + (transfer_finished ? @release_candy : 0)) * evolves) - (evolves * candy_needed)) / candy_needed
    end
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
  print 'Release safe Pokemon? (y/n) '
  @do_safe_release = gets.chomp.upcase == 'Y'
  print 'Release safe amount of unsafe Pokemon? (y/n) '
  @do_unsafe_release = gets.chomp.upcase == 'Y'
  print 'Evolve whitelisted species? (y/n) '
  @do_evolve = gets.chomp.upcase == 'Y'
end

@client = Poke::API::Client.new
@client.login(@username, @password, @method)

@client.get_inventory

response = @client.call.response
inventory = response[:GET_INVENTORY][:inventory_delta][:inventory_items].map { |x| x[:inventory_item_data] }

candy = inventory.map { |x| x[:pokemon_family] }.compact
family_candy = Hash[*candy.map { |c| [c[:family_id], c[:candy]] }.flatten]
pokemon = inventory.map { |x| x[:pokemon_data] if (x[:pokemon_data] and not x[:pokemon_data][:is_egg]) }.compact

poke_groups = pokemon.group_by { |pk| pk[:pokemon_id] }
family_groups = pokemon.group_by { |pk| @pokemon_families[pk[:pokemon_id]] }
pokemon_counts = Hash[*poke_groups.map { |type, pk_list| [type, pk_list.size] }.flatten]

irrelevant = family_groups.map { |family_type, family_list|
  family_list.find_all { |p1|
    family_list.any? { |p2|
      p1[:id] != p2[:id] and
          get_level(p1) <= get_level(p2) and
          p1[:individual_attack] <= p2[:individual_attack] and
          p1[:individual_defense] <= p2[:individual_defense] and
          p1[:individual_stamina] <= p2[:individual_stamina]
    }
  }
}.flatten
relevant = (pokemon - irrelevant).group_by { |pk| pk[:pokemon_id] }

unsafe = irrelevant.group_by { |x| x[:pokemon_id] }.find_all { |species, all_pk|
  current_candy = (family_candy[@pokemon_families[species]] or 0) + all_pk.size
  pokemon_counts[species] == all_pk.size or evolutions_possible(current_candy, @pokemon_evolution_candies[species], true) > relevant[species].size
}.map(&:last).flatten
unsafe_groups = unsafe.group_by { |pk| pk[:pokemon_id] }
safe = (irrelevant - unsafe)
safe_groups = safe.group_by { |pk| pk[:pokemon_id] }

evolve_list = []
total_evolutions = 0
poke_groups.each { |species, pk_list|
  current_candy = (family_candy[@pokemon_families[species]] or 0) + (safe_groups[species] or []).size
  relevant_species = (relevant[species] or [])
  unsafe_species = (unsafe_groups[species] or [])
  evo_able = evolutions_possible(current_candy, @pokemon_evolution_candies[species], true)
  relevant_count = relevant_species.size
  if @do_unsafe_release and evo_able < pk_list.size and evo_able > relevant_count
    drop_count = pk_list.size - evo_able
    release_unsafe_list = unsafe_groups[species].sample(drop_count)
    unsafe_groups[species] -= release_unsafe_list
    unsafe_species = (unsafe_groups[species] or [])
    unsafe -= release_unsafe_list
    safe += release_unsafe_list
    puts "#{species}: #{evo_able}/#{pk_list.size} [unsafe release count: #{release_unsafe_list.size}]"
  end
  if @evolution_whitelist.include? species
    total_evolutions += [evo_able, pk_list.size].min
    if evo_able > 0
      if evo_able < relevant_species.size
        evolve_list += find_best(relevant_species, evo_able)
      else
        evolve_list += relevant_species
        unsafe_evolves = evo_able - relevant_species.size
        if unsafe_evolves < unsafe_species.size
          evolve_list += find_best(unsafe_species, unsafe_evolves)
        else
          evolve_list += unsafe_species
        end
      end
    end
  end
}

puts "Total evolutions possible: #{total_evolutions}"

relevant_unnamed = relevant.map { |k, v| v }.flatten.find_all { |pk| pk[:nickname].empty? }
unsafe_unnamed = unsafe.find_all { |pk| pk[:nickname] != 'X' }
unsafe_unnamed.each { |pk| @client.nickname_pokemon(pokemon_id: pk[:id], nickname: 'X') }
relevant_unnamed.each { |pk| puts "Adding nickname of #{set_stat_nickname(pk)} to CP #{pk[:cp]} #{pk[:pokemon_id]}" }
puts "Marking unsafe: #{unsafe_unnamed.group_by { |pk| pk[:pokemon_id] }.map { |k, v| "#{v.size} #{k}" } * ', '}"

if @do_safe_release
  puts "Releasing #{safe.size} safe pokemon: #{safe.group_by { |pk| pk[:pokemon_id] }.map { |k, v| "#{v.size} #{k}" } * ', '}"
  safe.each { |pk| @client.release_pokemon(pokemon_id: pk[:id]) }
else
  puts "Marking safe pokemon: #{safe.group_by { |pk| pk[:pokemon_id] }.map { |k, v| "#{v.size} #{k}" } * ', '}"
  safe.find_all { |pk| pk[:nickname] != 'Release' }.each { |pk| @client.nickname_pokemon(pokemon_id: pk[:id], nickname: 'Release') }
end

puts "Actual evolutions that #{@do_evolve ? 'will' : 'would'} be done: #{evolve_list.size}"
evolve_list.group_by { |pk| pk[:pokemon_id] }.each { |species, pk_list|
  puts "Evolving #{pk_list.size} #{species}: #{pk_list.map { |pk| "L#{get_level(pk)}[#{pk[:nickname]}]" } * ', '}"
}
evolve_list.each { |pk| @client.evolve_pokemon(pokemon_id: pk[:id]) } if @do_evolve

puts @client.call.response
