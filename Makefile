/**
 * TitanMUD v18.0 - The Feature Complete Edition
 * Features: Formatted Help Screen, PvP Only, Static HUD, Stable UI, Full Commands
 *
 * COMPILE: g++ -std=c++17 -O2 titan_mud_v18.cpp -o titan_mud -I$(brew --prefix)/include -L$(brew --prefix)/lib -lpthread
 * RUN:     ./titan_mud
 */

#include <iostream>
#include <string>
#include <vector>
#include <map>
#include <memory>
#include <sstream>
#include <algorithm>
#include <deque>
#include <set>
#include <random>
#include <iomanip>
#include <chrono> 
#include <boost/asio.hpp>
#include <boost/algorithm/string.hpp>

using boost::asio::ip::tcp;

// --- ANSI Colors ---
const std::string C_RESET   = "\033[0m";
const std::string C_RED     = "\033[31m";
const std::string C_GREEN   = "\033[32m";
const std::string C_YELLOW  = "\033[33m";
const std::string C_BLUE    = "\033[34m";
const std::string C_MAGENTA = "\033[35m";
const std::string C_CYAN    = "\033[36m";
const std::string C_WHITE   = "\033[37m";
const std::string C_BOLD    = "\033[1m";

// --- Terminal Control ---
const std::string I_CLS     = "\033[2J"; 
const std::string I_HOME    = "\033[H";

// --- Forward Declarations ---
class Player;
class Mob;
class Room;
class World;

struct Stats {
    int level = 1;
    int xp = 0;
    int max_xp = 100;
    int hp = 100;
    int max_hp = 100;
    int mana = 50;
    int max_mana = 50;
    int damage = 10;
    int gold = 0;
};

class LivingEntity {
public:
    std::string name;
    std::string description;
    Stats stats;
    int current_room_id = 0;
    std::shared_ptr<LivingEntity> combat_target = nullptr;
    
    // Cooldown management
    std::chrono::steady_clock::time_point last_attack_time;

    virtual ~LivingEntity() = default;
    virtual void send_msg(const std::string& msg) {} 
    virtual bool is_player() const { return false; }
    
    // Cooldown: 1.0 second
    bool can_attack() {
        auto now = std::chrono::steady_clock::now();
        if (std::chrono::duration_cast<std::chrono::milliseconds>(now - last_attack_time).count() >= 1000) {
            last_attack_time = now;
            return true;
        }
        return false;
    }
};

enum class ItemType { WEAPON, POTION, MISC };
class Item {
public:
    std::string name;
    std::string description;
    ItemType type;
    int value; 
    int cost;  
    Item(std::string n, std::string d, ItemType t, int v, int c) : name(n), description(d), type(t), value(v), cost(c) {}
};

class Mob : public LivingEntity {
public:
    // Mobs are now passive scenery
    Mob(std::string n, std::string d) {
        name = n; description = d;
        stats.hp = 1; stats.max_hp = 1; 
    }
    bool is_player() const override { return false; }
};

class Room {
public:
    int id;
    std::string title;
    std::string description;
    bool is_shop = false;
    std::map<std::string, int> exits;
    std::vector<std::shared_ptr<Player>> players;
    std::vector<std::shared_ptr<Mob>> mobs;
    std::vector<std::shared_ptr<Item>> items; 
    std::vector<std::shared_ptr<Item>> shop_inventory; 
    Room(int i, std::string t, std::string d) : id(i), title(t), description(d) {}
};

enum class ClassType { WARRIOR, MAGE };

class Player : public LivingEntity, public std::enable_shared_from_this<Player> {
public:
    tcp::socket socket_;
    ClassType p_class;
    bool logged_in = false;
    bool choosing_class = false; 
    
    std::vector<std::shared_ptr<Item>> inventory;
    std::shared_ptr<Item> equipped_weapon = nullptr;
    std::deque<std::string> message_log; 
    
    enum { max_length = 4096 };
    char read_buffer_[max_length];
    std::deque<std::string> write_queue_;

    World& world_ref;

    Player(tcp::socket socket, World& world);

    bool is_player() const override { return true; }
    void send_msg(const std::string& msg) override { send(msg); }

    void start();
    void send(const std::string& msg);
    void refresh_screen(); 
    void disconnect();
    void do_tick();
    void on_input(std::string cmd);
    void gain_xp(int amount);
    void heal(int amount);
    void draw_hud();
    void show_help();
    std::string get_class_name() const { return (p_class == ClassType::WARRIOR ? "Warrior" : "Mage"); }

private:
    void do_read();
    void do_write();
    void process_command(std::string verb, std::string arg);
};

class World {
public:
    std::map<int, std::unique_ptr<Room>> rooms;
    std::vector<std::shared_ptr<Player>> all_players;
    
    World() { build_world(); }

    void build_world() {
        auto r0 = std::make_unique<Room>(0, "Oakhaven Plaza", "North: Shop | East: Arena | West: Woods");
        r0->exits["north"] = 3; r0->exits["east"] = 1; r0->exits["west"] = 2;
        rooms[0] = std::move(r0);

        auto r1 = std::make_unique<Room>(1, "The Blood Arena", "Red sand covers the floor. The perfect place for a duel.");
        r1->exits["west"] = 0;
        r1->mobs.push_back(std::make_shared<Mob>("Rat", "A giant rat scurring about (harmless)."));
        rooms[1] = std::move(r1);

        auto r2 = std::make_unique<Room>(2, "Whispering Woods", "Dark trees surround you.");
        r2->exits["east"] = 0; r2->exits["north"] = 4;
        auto wolf = std::make_shared<Mob>("Direwolf", "A black wolf watching from the shadows.");
        r2->mobs.push_back(wolf);
        rooms[2] = std::move(r2);

        auto r3 = std::make_unique<Room>(3, "Magic Shop", "Smells of sulfur.");
        r3->is_shop = true; r3->exits["south"] = 0;
        r3->shop_inventory.push_back(std::make_shared<Item>("potion", "Red Potion", ItemType::POTION, 50, 10));
        r3->shop_inventory.push_back(std::make_shared<Item>("sword", "Steel Sword", ItemType::WEAPON, 20, 100));
        rooms[3] = std::move(r3);

        auto r4 = std::make_unique<Room>(4, "Tower Entrance", "The ruined tower.");
        r4->exits["south"] = 2; r4->exits["up"] = 5;
        auto skel = std::make_shared<Mob>("Skeleton", "A pile of bones.");
        r4->mobs.push_back(skel);
        rooms[4] = std::move(r4);

        auto r5 = std::make_unique<Room>(5, "Malagor's Sanctum", "Green fire burns here.");
        r5->exits["down"] = 4;
        auto boss = std::make_shared<Mob>("Malagor", "The Necromancer (Observing).");
        r5->mobs.push_back(boss);
        rooms[5] = std::move(r5);
    }

    Room* get_room(int id) {
        if (rooms.count(id)) return rooms[id].get();
        return nullptr;
    }

    std::shared_ptr<Player> find_player_global(std::string name) {
        for(auto& p : all_players) if(boost::iequals(p->name, name) && p->logged_in) return p;
        return nullptr;
    }

    void broadcast_room(int room_id, std::string msg, std::shared_ptr<Player> ignore = nullptr) {
        Room* r = get_room(room_id);
        if (!r) return;
        for (auto& p : r->players) {
            if (p != ignore && p->logged_in) p->send(msg); 
        }
    }

    void broadcast_global(std::string msg) {
        for (auto& p : all_players) if (p->logged_in) p->send(msg);
    }
};

Player::Player(tcp::socket socket, World& world) 
    : socket_(std::move(socket)), world_ref(world) {}

void Player::start() {
    auto self(shared_from_this());
    boost::asio::async_write(socket_, boost::asio::buffer(I_CLS + I_HOME),
        [this, self](boost::system::error_code ec, std::size_t) {
            if(!ec) {
                std::string banner = C_CYAN + C_BOLD + 
R"(
  _______ _ _                 __  __ _   _ _____  
 |__   __(_) |               |  \/  | | | |  __ \ 
    | |   _| |_ __ _ _ __    | \  / | | | | |  | |
    | |  | | __/ _` | '_ \   | |\/| | | | | |  | |
    | |  | | || (_| | | | |  | |  | | |_| | |__| |
    |_|  |_|\__\__,_|_| |_|  |_|  |_|\___/|_____/ 
                                                  
     >>> THE CURSE OF MALAGOR - v18.0 <<<
)" + C_RESET + "\r\n\r\nWhat is your name, hero? ";
                boost::asio::async_write(socket_, boost::asio::buffer(banner),
                    [this, self](boost::system::error_code, std::size_t){});
                do_read();
            }
        });
}

void Player::disconnect() { if (socket_.is_open()) socket_.close(); }

void Player::send(const std::string& msg) {
    if (!logged_in) {
        bool write_in_progress = !write_queue_.empty();
        write_queue_.push_back(msg);
        if (!write_in_progress) do_write();
        return;
    }
    message_log.push_back(msg);
    if (message_log.size() > 20) message_log.pop_front(); 
    refresh_screen();
}

// --- UI RENDERER ---
void Player::refresh_screen() {
    std::stringstream screen;
    screen << I_CLS << I_HOME; 

    // --- HUD: PLAYER STATUS ---
    std::string hp_color = (stats.hp < stats.max_hp/3) ? C_RED : C_GREEN;
    screen << "\033[44m" << C_WHITE << C_BOLD 
           << std::left << std::setw(10) << name 
           << " HP:" << hp_color << std::setw(7) << (std::to_string(stats.hp) + "/" + std::to_string(stats.max_hp)) << C_WHITE
           << " MP:" << C_CYAN << std::setw(7) << (std::to_string(stats.mana) + "/" + std::to_string(stats.max_mana)) << C_WHITE
           << " Lvl:" << std::setw(2) << stats.level 
           << " GP:" << C_YELLOW << std::setw(4) << stats.gold
           << C_RESET << "\033[K\r\n";

    // --- HUD: TARGET STATUS ---
    if (combat_target) {
        std::string t_hp_color = (combat_target->stats.hp < combat_target->stats.max_hp/3) ? C_RED : C_YELLOW;
        screen << "\033[41m" << C_WHITE << C_BOLD 
               << " TARGET: " << std::left << std::setw(15) << combat_target->name
               << " HP: " << t_hp_color << combat_target->stats.hp << "/" << combat_target->stats.max_hp
               << C_RESET << "\033[K\r\n";
    } else {
        screen << "\033[40m" << C_BOLD << " [SAFE]" << C_RESET << "\033[K\r\n";
    }

    // --- GAME LOG ---
    screen << "\r\n";
    for(const auto& line : message_log) {
        screen << line << "\r\n";
    }

    // --- PROMPT ---
    screen << "\r\n" << C_YELLOW << "> " << C_RESET; 

    bool write_in_progress = !write_queue_.empty();
    write_queue_.push_back(screen.str());
    if (!write_in_progress) do_write();
}

void Player::do_write() {
    auto self(shared_from_this());
    boost::asio::async_write(socket_,
        boost::asio::buffer(write_queue_.front().data(), write_queue_.front().length()),
        [this, self](boost::system::error_code ec, std::size_t) {
            if (!ec) {
                write_queue_.pop_front();
                if (!write_queue_.empty()) do_write();
            } else { disconnect(); }
        });
}

void Player::do_read() {
    auto self(shared_from_this());
    socket_.async_read_some(boost::asio::buffer(read_buffer_, max_length),
        [this, self](boost::system::error_code ec, std::size_t length) {
            if (!ec) {
                std::string data(read_buffer_, length);
                static std::string buffer;
                buffer += data;
                size_t pos;
                while ((pos = buffer.find('\n')) != std::string::npos) {
                    std::string line = buffer.substr(0, pos);
                    boost::trim(line); 
                    buffer.erase(0, pos + 1);
                    if(!line.empty()) on_input(line);
                }
                do_read();
            } else {
                if (logged_in) {
                    Room* r = world_ref.get_room(current_room_id);
                    if(r) {
                        auto it = std::find(r->players.begin(), r->players.end(), shared_from_this());
                        if(it != r->players.end()) r->players.erase(it);
                    }
                    world_ref.broadcast_global(C_YELLOW + name + " has left." + C_RESET);
                }
                auto it = std::find(world_ref.all_players.begin(), world_ref.all_players.end(), shared_from_this());
                if(it != world_ref.all_players.end()) world_ref.all_players.erase(it);
            }
        });
}

void Player::on_input(std::string cmd) {
    if (!logged_in) {
        if (!choosing_class) {
            name = cmd;
            choosing_class = true;
            std::string msg = "Class [Warrior/Mage]: ";
            boost::asio::async_write(socket_, boost::asio::buffer(msg), [](auto,auto){});
        } else {
            if (boost::iequals(cmd, "Warrior") || boost::iequals(cmd, "w")) {
                p_class = ClassType::WARRIOR;
                stats.max_hp = 200; stats.hp = 200; stats.damage = 15;
            } else {
                p_class = ClassType::MAGE;
                stats.max_hp = 100; stats.hp = 100; stats.max_mana = 100; stats.mana = 100; stats.damage = 5;
                inventory.push_back(std::make_shared<Item>("staff", "Old Staff", ItemType::WEAPON, 5, 0));
            }
            logged_in = true;
            stats.gold = 50; 
            Room* r = world_ref.get_room(0);
            r->players.push_back(shared_from_this());
            send(C_GREEN + "Welcome, " + name + "!" + C_RESET);
            send("Type " + C_BOLD + "help" + C_RESET + " for commands.");
            process_command("look", "");
        }
        return;
    }

    std::vector<std::string> parts;
    boost::split(parts, cmd, boost::is_any_of(" "));
    std::string verb = boost::algorithm::to_lower_copy(parts[0]);
    std::string arg = (parts.size() > 1) ? cmd.substr(parts[0].length() + 1) : "";
    message_log.push_back(C_YELLOW + "> " + cmd + C_RESET);
    if(message_log.size() > 20) message_log.pop_front();
    process_command(verb, arg);
}

// --- RESTORED HELP SCREEN ---
void Player::show_help() {
    std::string line = C_BLUE + " +------------------------------------------------------------+" + C_RESET;
    std::string pipe = C_BLUE + " | " + C_RESET;
    std::string endp = C_BLUE + " |" + C_RESET;
    
    send(line);
    send(pipe + C_YELLOW + C_BOLD + "                     TITAN MUD COMMANDS                     " + endp);
    send(line);
    
    send(pipe + C_CYAN + " [ MOVEMENT ]                                               " + endp);
    send(pipe + C_WHITE + "  n, s, e, w, u, d   " + C_RESET + "Move in compass directions             " + endp);
    send(pipe + C_CYAN + " [ PVP COMBAT ]                                             " + endp);
    send(pipe + C_WHITE + "  kill <player>      " + C_RESET + "Attack another player                  " + endp);
    send(pipe + C_WHITE + "  cast <spell> <tgt> " + C_RESET + "Cast: fireball (15m), heal (20m)       " + endp);
    send(pipe + C_CYAN + " [ INTERACTION ]                                            " + endp);
    send(pipe + C_WHITE + "  look, examine <tgt>" + C_RESET + "Inspect room or entity                 " + endp);
    send(pipe + C_WHITE + "  get, drop, give    " + C_RESET + "Manage items                           " + endp);
    send(pipe + C_WHITE + "  inv, wield, use    " + C_RESET + "Check gear, equip weapon, drink potion " + endp);
    send(pipe + C_CYAN + " [ SOCIAL ]                                                 " + endp);
    send(pipe + C_WHITE + "  say, yell          " + C_RESET + "Talk to room / server                  " + endp);
    send(pipe + C_WHITE + "  tell <name> <msg>  " + C_RESET + "Whisper privately                      " + endp);
    send(pipe + C_WHITE + "  emote <action>     " + C_RESET + "Roleplay (e.g., 'emote laughs')        " + endp);
    send(pipe + C_WHITE + "  who                " + C_RESET + "List online heroes                     " + endp);
    send(pipe + C_CYAN + " [ SHOP ]                                                   " + endp);
    send(pipe + C_WHITE + "  list, buy <item>   " + C_RESET + "Interact with shops                    " + endp);
    send(line);
}

void Player::process_command(std::string verb, std::string arg) {
    Room* r = world_ref.get_room(current_room_id);

    if (verb == "quit") { send("Goodbye."); disconnect(); }
    else if (verb == "help") show_help();
    // --- SOCIAL ---
    else if (verb == "who") {
        send(C_BOLD + "--- ONLINE ---" + C_RESET);
        for(auto& p : world_ref.all_players) {
            if(p->logged_in) send(C_GREEN + p->name + C_RESET + " [" + p->get_class_name() + "] Lvl " + std::to_string(p->stats.level));
        }
    }
    else if (verb == "say") world_ref.broadcast_room(current_room_id, C_CYAN + name + ": " + arg + C_RESET);
    else if (verb == "yell") world_ref.broadcast_global(C_RED + C_BOLD + name + " yells: " + arg + C_RESET);
    else if (verb == "emote") world_ref.broadcast_room(current_room_id, C_CYAN + name + " " + arg + C_RESET);
    else if (verb == "tell") {
        std::stringstream ss(arg); std::string target_name, msg; ss >> target_name; getline(ss, msg);
        auto target = world_ref.find_player_global(target_name);
        if (target) {
            send(C_MAGENTA + "You tell " + target->name + ":" + msg + C_RESET);
            target->send(C_MAGENTA + name + " tells you:" + msg + C_RESET);
        } else send("Player not found.");
    }
    // --- GIVE ---
    else if (verb == "give") {
        std::stringstream ss(arg); std::string item_name, target_name; ss >> item_name >> target_name;
        auto it_item = std::find_if(inventory.begin(), inventory.end(), [&](auto& i){ return boost::iequals(i->name, item_name); });
        auto it_player = std::find_if(r->players.begin(), r->players.end(), [&](auto& p){ return boost::iequals(p->name, target_name); });
        
        if (it_item == inventory.end()) { send("You don't have that."); return; }
        if (it_player == r->players.end()) { send("Player not here."); return; }
        if (*it_player == shared_from_this()) { send("You keep it."); return; }
        
        (*it_player)->inventory.push_back(*it_item);
        if (equipped_weapon == *it_item) equipped_weapon = nullptr;
        inventory.erase(it_item);
        send("You gave " + item_name + " to " + target_name + ".");
        (*it_player)->send(C_GREEN + name + " gave you " + item_name + "." + C_RESET);
    }
    // --- EXAMINE ---
    else if (verb == "examine") {
        auto it_ri = std::find_if(r->items.begin(), r->items.end(), [&](auto& i){ return boost::iequals(i->name, arg); });
        if (it_ri != r->items.end()) { send((*it_ri)->description); return; }
        auto it_m = std::find_if(r->mobs.begin(), r->mobs.end(), [&](auto& m){ return boost::iequals(m->name, arg); });
        if (it_m != r->mobs.end()) { send((*it_m)->description); return; }
        auto it_p = std::find_if(r->players.begin(), r->players.end(), [&](auto& p){ return boost::iequals(p->name, arg); });
        if (it_p != r->players.end()) { send((*it_p)->description); return; }
        auto it_i = std::find_if(inventory.begin(), inventory.end(), [&](auto& i){ return boost::iequals(i->name, arg); });
        if (it_i != inventory.end()) { send((*it_i)->description); return; }
        send("You don't see that.");
    }
    // --- COMBAT ---
    else if (verb == "kill" || verb == "k") {
        auto it_m = std::find_if(r->mobs.begin(), r->mobs.end(), [&](auto& m){ return boost::iequals(m->name, arg); });
        if (it_m != r->mobs.end()) {
            send(C_YELLOW + "The creatures here are not worth your time. Only players are worthy foes." + C_RESET);
            return;
        }
        auto it_p = std::find_if(r->players.begin(), r->players.end(), [&](auto& p){ return boost::iequals(p->name, arg); });
        if (it_p != r->players.end()) {
            if (*it_p == shared_from_this()) { send("You can't kill yourself."); return; }
            combat_target = *it_p;
            // Immediate Attack
            combat_target->last_attack_time = std::chrono::steady_clock::now() - std::chrono::seconds(10);
            last_attack_time = std::chrono::steady_clock::now() - std::chrono::seconds(10);
            
            (*it_p)->send_msg(C_RED + C_BOLD + name + " is ATTACKING YOU!" + C_RESET);
            send(C_RED + "You attack " + (*it_p)->name + "!" + C_RESET);
            return;
        }
        send("Kill who?");
    }
    // --- ITEMS / SHOP ---
    else if (verb == "inv" || verb == "i") {
        send("Inventory:");
        for(auto& i : inventory) send("- " + i->name + (equipped_weapon==i ? " (equipped)" : ""));
    }
    else if (verb == "get") {
        auto it = std::find_if(r->items.begin(), r->items.end(), [&](auto& i){ return boost::iequals(i->name, arg); });
        if (it != r->items.end()) {
            inventory.push_back(*it);
            send("You pick up " + (*it)->name + ".");
            world_ref.broadcast_room(current_room_id, name + " picks up " + (*it)->name + ".", shared_from_this());
            r->items.erase(it);
        } else send("Don't see that.");
    }
    else if (verb == "drop") {
        auto it = std::find_if(inventory.begin(), inventory.end(), [&](auto& i){ return boost::iequals(i->name, arg); });
        if (it != inventory.end()) {
            if (equipped_weapon == *it) equipped_weapon = nullptr;
            r->items.push_back(*it);
            send("You drop " + (*it)->name + ".");
            world_ref.broadcast_room(current_room_id, name + " drops " + (*it)->name + ".", shared_from_this());
            inventory.erase(it);
        } else send("Don't have that.");
    }
    else if (verb == "wield") {
        auto it = std::find_if(inventory.begin(), inventory.end(), [&](auto& i){ return boost::iequals(i->name, arg); });
        if (it != inventory.end() && (*it)->type == ItemType::WEAPON) {
            equipped_weapon = *it;
            send("You wield " + (*it)->name + ".");
        } else send("Cannot wield.");
    }
    else if (verb == "use") {
         auto it = std::find_if(inventory.begin(), inventory.end(), [&](auto& i){ return boost::iequals(i->name, arg); });
         if (it != inventory.end() && (*it)->type == ItemType::POTION) {
             heal((*it)->value); inventory.erase(it);
             send("You drink the potion.");
         } else send("Cannot drink.");
    }
    else if (verb == "list") {
        if (!r->is_shop) { send("Not a shop."); return; }
        send("For Sale:");
        for(auto& i : r->shop_inventory) send(C_GREEN + i->name + C_RESET + " - " + std::to_string(i->cost) + " gold");
    }
    else if (verb == "buy") {
        if (!r->is_shop) { send("Not a shop."); return; }
        auto it = std::find_if(r->shop_inventory.begin(), r->shop_inventory.end(), [&](auto& i){ return boost::iequals(i->name, arg); });
        if (it != r->shop_inventory.end()) {
            if (stats.gold >= (*it)->cost) {
                stats.gold -= (*it)->cost;
                inventory.push_back(std::make_shared<Item>(*(*it)));
                send("Bought " + (*it)->name + ".");
            } else send("Not enough gold.");
        } else send("Not for sale.");
    }
    // --- MOVEMENT ---
    else if (verb == "n" || verb == "s" || verb == "e" || verb == "w" || verb == "u" || verb == "d") {
        std::string dir = (verb=="n")?"north":(verb=="s")?"south":(verb=="e")?"east":(verb=="w")?"west":(verb=="u")?"up":"down";
        if (r->exits.count(dir)) {
            auto it = std::find(r->players.begin(), r->players.end(), shared_from_this());
            r->players.erase(it);
            world_ref.broadcast_room(current_room_id, name + " leaves " + dir + ".");
            current_room_id = r->exits[dir];
            r = world_ref.get_room(current_room_id);
            r->players.push_back(shared_from_this());
            world_ref.broadcast_room(current_room_id, name + " arrives.", shared_from_this());
            process_command("look", "");
            combat_target = nullptr; 
        } else send("Can't go that way.");
    }
    // --- BASIC ---
    else if (verb == "look" || verb == "l") {
        send(C_CYAN + C_BOLD + r->title + C_RESET + "\r\n" + r->description);
        send(C_YELLOW + "Exits: "); for(auto& [d,i] : r->exits) send(d + " ");
        if(r->is_shop) send(C_GREEN + "Type 'list' to shop." + C_RESET);
        for(auto& i : r->items) send(C_MAGENTA + i->name + " is here." + C_RESET);
        for(auto& m : r->mobs) send(C_RED + m->name + " (" + m->description + ")" + C_RESET);
        for(auto& p : r->players) if(p!=shared_from_this()) send(C_WHITE + p->name + " is here." + C_RESET);
    }
    // --- CAST ---
    else if (verb == "cast") {
        if (p_class != ClassType::MAGE) { send("Mages only."); return; }
        std::stringstream ss(arg); std::string spell, target_name; ss >> spell >> target_name;
        if (spell == "heal") {
            if (stats.mana < 20) { send("No mana."); return; }
            std::shared_ptr<Player> target = nullptr;
            if (target_name.empty()) target = shared_from_this();
            else {
                auto it = std::find_if(r->players.begin(), r->players.end(), [&](auto& p){ return boost::iequals(p->name, target_name); });
                if (it != r->players.end()) target = *it;
            }
            if (target) {
                stats.mana -= 20; target->heal(40);
                send(C_BLUE + "You heal " + target->name + "." + C_RESET);
                if(target!=shared_from_this()) target->send(C_BLUE + name + " heals you." + C_RESET);
            } else send("Who?");
        } else if (spell == "fireball") {
             if (stats.mana < 15) { send("No mana."); return; }
             
             // PvP Check for Fireball
             auto it_p = std::find_if(r->players.begin(), r->players.end(), [&](auto& p){ return boost::iequals(p->name, target_name); });
             if (it_p == r->players.end()) { send("No player found."); return; }
             
             combat_target = *it_p;
             stats.mana -= 15; 
             combat_target->stats.hp -= 40;
             send(C_BLUE + "Fireball hits " + combat_target->name + " for 40!" + C_RESET);
             combat_target->send_msg(C_RED + "Fireball hits you for 40!" + C_RESET);
        }
    }
    else { send("Unknown."); }
}

void Player::gain_xp(int amount) {
    stats.xp += amount;
    if (stats.xp >= stats.max_xp) {
        stats.level++; stats.xp = 0; stats.max_xp *= 1.5;
        stats.max_hp += 20; stats.hp = stats.max_hp;
        send(C_YELLOW + C_BOLD + "LEVEL UP! You are level " + std::to_string(stats.level) + "!" + C_RESET);
    }
    refresh_screen();
}

void Player::heal(int amount) {
    stats.hp += amount;
    if (stats.hp > stats.max_hp) stats.hp = stats.max_hp;
    refresh_screen();
}

void Player::do_tick() {
    if (!logged_in) return;
    
    bool updated = false;
    if (rand()%20==0 && stats.hp < stats.max_hp) { stats.hp++; updated=true; }
    if (rand()%15==0 && stats.mana < stats.max_mana) { stats.mana++; updated=true; }
    if (updated) refresh_screen();

    if (combat_target) {
        if (combat_target->current_room_id != current_room_id) {
            send(C_YELLOW + "Target fled!" + C_RESET); 
            combat_target = nullptr; 
            return;
        }

        if (can_attack()) {
            int dmg = stats.damage;
            combat_target->stats.hp -= dmg;
            send(C_GREEN + "You hit " + combat_target->name + " for " + std::to_string(dmg) + "." + C_RESET);
            combat_target->send_msg(C_RED + name + " hits you for " + std::to_string(dmg) + "!" + C_RESET);

            if (combat_target->stats.hp <= 0) {
                send(C_YELLOW + "You killed " + combat_target->name + "!" + C_RESET);
                
                // PvP Death Logic
                world_ref.broadcast_global(C_RED + C_BOLD + combat_target->name + " was slain by " + name + "!" + C_RESET);
                auto victim = std::dynamic_pointer_cast<Player>(combat_target);
                victim->send(C_RED + "YOU DIED." + C_RESET);
                victim->stats.hp = victim->stats.max_hp;
                victim->current_room_id = 0; 
                Room* r = world_ref.get_room(current_room_id);
                auto it = std::find(r->players.begin(), r->players.end(), victim);
                r->players.erase(it);
                Room* town = world_ref.get_room(0);
                town->players.push_back(victim);
                victim->combat_target = nullptr;
                victim->refresh_screen();
                
                combat_target = nullptr;
            }
        }
        refresh_screen(); 
    }
}

class Engine {
public:
    World world;
    boost::asio::io_context io_context;
    tcp::acceptor acceptor;
    bool running = true;

    Engine(int port) : acceptor(io_context, tcp::endpoint(tcp::v4(), port)) { do_accept(); }

    void do_accept() {
        acceptor.async_accept([this](boost::system::error_code ec, tcp::socket socket) {
            if (!ec) {
                auto p = std::make_shared<Player>(std::move(socket), world);
                world.all_players.push_back(p);
                p->start();
            }
            do_accept();
        });
    }

    void run_loop() {
        std::thread net_thread([this](){ io_context.run(); });
        std::cout << "TitanMUD v18.0 running on 4000...\n";
        while(running) {
            for(auto& p : world.all_players) p->do_tick();
            // Mobs are scenery now, so no loop needed for them.
            std::this_thread::sleep_for(std::chrono::milliseconds(250)); // Slow tick rate
        }
        net_thread.join();
    }
};

int main() {
    try { Engine e(4000); e.run_loop(); } 
    catch (std::exception& e) { std::cerr << e.what() << "\n"; }
    return 0;
}
