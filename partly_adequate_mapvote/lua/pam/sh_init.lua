require("pacoman")

PAM = {}

--the possible states
--for when it hasn't started yet
PAM.STATE_DISABLED = 0
--for when voting is possible
PAM.STATE_STARTED = 1
--for when the winner is announced
PAM.STATE_FINISHED = 2

--the current state
PAM.state = PAM.STATE_DISABLED

-- vote type callbacks
PAM.type_callbacks = {}

--the voteable maps
PAM.options = {}
PAM.option_count = 0
PAM.special_option_count = 0

-- stores the winner when there is one
PAM.winning_option = nil

--the votes
PAM.votes = {}
