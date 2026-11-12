"""Saved sights get a day before the days are filled (plan_engine.assign_pins).

Seen in a real Rome plan: 26 must-sees for four and a half days. The most famous go first, a day holds what its
sightseeing hours and visit budget allow, a winter-closing site isn't put on a short arrival afternoon, the
departure morning only takes what is by the stay, and a saved part of a group (the Sistine Chapel) brings its lead."""
from trippy.planner.plan_engine import assign_pins

DATES = ['2027-01-09', '2027-01-10', '2027-01-11', '2027-01-12', '2027-01-13']


def pin(pid, lat, lon, fame=0, category='attraction', minutes=60, priority=100):
    tags = [f'notable:{fame}'] if fame else []
    return {'id': pid, 'name': pid, 'category': category, 'tags': tags, 'personal_priority': priority,
            'coordinates': {'latitude': lat, 'longitude': lon}, 'average_visit_minutes': minutes, 'duration_basis': 'source'}


def run(places, brief=None, area_plan=None, members_of=None, base=None):
    brief = brief or {'date_range': {'arrival_time': '12:00', 'departure_time': '13:00'}}
    area_plan = area_plan or {d: [] for d in DATES}
    return assign_pins(places, DATES, brief, area_plan=area_plan, area_of={}, area_by_id={}, base_place=base,
                       grouped={m['id'] for ms in (members_of or {}).values() for m in ms}, pace='balanced',
                       visits={'attraction', 'museum', 'nature'}, members_of=members_of or {})


def test_famous_first_and_overflow_left_for_the_list():
    # Twenty hour-long sights for three full days and an arrival afternoon: not all fit.
    places = [pin(f'p{i:02d}', 41.89 + i / 1000, 12.48, fame=200 - i) for i in range(20)]
    out = run(places)
    assert 'p00' in out and 'p01' in out                     # the most famous always get a day
    assert len(out) < 20                                      # the rest are left for "didn't fit", not crammed in
    assert '2027-01-13' not in out.values()                   # a 13:00 flight leaves no sightseeing morning


def test_unknown_fame_ranks_with_the_typical_pin_not_last():
    places = [pin(f'p{i:02d}', 41.89, 12.48 + i / 1000, fame=100 - i) for i in range(18)]
    places.append(pin('Colosseum', 41.8902, 12.4922, fame=0))
    out = run(places)
    assert 'Colosseum' in out
    assert 'p17' not in out or len(out) == len(places)        # a weaker known pin gives way first


def test_winter_ruins_skip_the_short_arrival_afternoon():
    ruins = pin('Forum', 41.8925, 12.4853, fame=150, minutes=90)
    ruins['category'] = 'attraction'
    out = run([ruins])
    # Landing 12:00 → free 13:30; with lunch and the ride, 90 minutes doesn't end before a 16:30 winter close.
    assert out['Forum'] != '2027-01-09'


def test_departure_morning_only_near_the_stay():
    base = {'id': 'base', 'coordinates': {'latitude': 41.9000, 'longitude': 12.4700}}
    brief = {'date_range': {'arrival_time': '09:00', 'departure_time': '18:00'}}
    near = pin('near', 41.9005, 12.4705, fame=10, minutes=30)
    far = pin('far', 41.8500, 12.5500, fame=10, minutes=30)
    # Fill every other day so the last one is the only room left.
    filler = [pin(f'f{i}', 41.9 + i / 1000, 12.47, fame=500, minutes=120) for i in range(16)]
    out = run(filler + [near, far], brief=brief, base=base)
    assert out.get('far') != '2027-01-13'
    assert out.get('near') in DATES


def test_a_saved_member_brings_its_group_lead():
    museums = pin('Vatican Museums', 41.9065, 12.4536, fame=65, category='museum', minutes=150, priority=0)
    chapel = pin('Sistine Chapel', 41.9029, 12.4545, fame=90, minutes=30)
    out = run([museums, chapel], members_of={'Vatican Museums': [chapel]})
    assert 'Vatican Museums' in out and 'Sistine Chapel' not in out


# Unpicked saves ("ideas"): they compete for open slots with a capped boost, never forced in.
from trippy.planner.plan_engine import IDEAS_PER_DAY, idea_bonus, is_idea


def idea(category='attraction', nodes=1, notes=''):
    p = pin('idea', 41.39, 2.17, category=category, priority=30)
    p['library_node_ids'] = [f'idea:{i}' for i in range(nodes)]
    p['description'] = notes
    return p


def test_what_counts_as_an_idea():
    assert is_idea(idea())
    assert not is_idea(pin('picked', 41.39, 2.17))                              # picked/pinned (100) leads outright
    community = idea(); community['tags'] = ['source:community']; community['personal_priority'] = 10
    assert not is_idea(community)                                                # other people's videos: a nudge only


def test_idea_bonus_is_evidence_and_capped():
    bare = idea_bonus(idea())
    noted = idea_bonus(idea(notes='Go before 13:00, cash only'))
    in_three_videos = idea_bonus(idea(nodes=3, notes='Best vermouth in El Born'))
    assert bare < 0 < noted < in_three_videos <= 24                              # a bare save gives some of its boost back
    assert idea_bonus(idea('food', nodes=3, notes='Best bombas')) == 1.5 * in_three_videos   # tested food counts more
    assert IDEAS_PER_DAY == 2
