
// src/utils/gameLogic.js

// Helper to clone players so we don't mutate the original data during a match
export const cloneTeam = (team) => {
  return {
    ...team,
    players: team.players.map(p => ({ ...p, stamina: p.physical || 80, matchRating: 6.0 }))
  };
};

export const calculateTeamStats = (players) => {
  // We assume the first 11 are the starters
  const starters = players.slice(0, 11);
  if (starters.length === 0) return { overall: 0, attack: 0, midfield: 0, defense: 0 };

  const totalRating = starters.reduce((acc, p) => acc + p.rating, 0);
  const overall = totalRating / starters.length;

  const forwards = starters.filter(p => p.position === 'FWD');
  const mids = starters.filter(p => p.position === 'MID');
  const defs = starters.filter(p => p.position === 'DEF' || p.position === 'GK');

  const attack = forwards.length ? forwards.reduce((acc, p) => acc + p.rating, 0) / forwards.length : 0;
  const midfield = mids.length ? mids.reduce((acc, p) => acc + p.rating, 0) / mids.length : 0;
  const defense = defs.length ? defs.reduce((acc, p) => acc + p.rating, 0) / defs.length : 0;

  return {
    overall: Math.round(overall),
    attack: Math.round(attack),
    midfield: Math.round(midfield),
    defense: Math.round(defense)
  };
};

export const getStarRating = (overall) => {
  if (overall >= 90) return 5;
  if (overall >= 75) return 4;
  if (overall >= 60) return 3;
  if (overall >= 45) return 2;
  return 1;
};

const random = (min, max) => Math.floor(Math.random() * (max - min + 1)) + min;

const attemptGoal = (attacker, defenderTeam) => {
  const defenseStats = calculateTeamStats(defenderTeam.players);
  const defenseStrength = defenseStats.defense;

  // Attacker skill + variance vs Defense skill + variance
  const shootRoll = (attacker.shooting * 0.6 + attacker.rating * 0.4) + random(-10, 20);
  const defenseRoll = (defenseStrength * 0.8 + 20) + random(-10, 20);

  return shootRoll > defenseRoll;
};

// Logic for substitution
const checkSubstitution = (team, minute, subsUsed) => {
  if (subsUsed >= 5) return null; // Max 5 subs

  // 1. Injury (Rare)
  // 2. Low Stamina (< 30)
  // 3. Bad Rating (< 5.0) - not implemented fully yet
  // 4. Tactical (losing late game) - optional

  const starters = team.players.slice(0, 11);
  const bench = team.players.slice(11);

  // Find tired player
  const tiredPlayerIndex = starters.findIndex(p => p.stamina < 30);

  if (tiredPlayerIndex !== -1 && bench.length > 0) {
    const playerOut = starters[tiredPlayerIndex];
    // Find replacement of same position preference
    let replacementIndex = bench.findIndex(p => p.position === playerOut.position);
    if (replacementIndex === -1) replacementIndex = 0; // fallback to first bench player

    return {
      type: 'sub',
      playerOutIndex: tiredPlayerIndex, // index in the full array (0-10)
      playerInIndex: 11 + replacementIndex // index in the full array (11+)
    };
  }

  return null;
};

export const simulateMinute = (matchState) => {
  // Deep clone needed for complex state?
  // For performance in React, we usually do shallow copies of changed parts.
  // Here, we have nested objects (teams -> players).
  // We'll do a careful structured clone or spread.

  const newState = {
    ...matchState,
    time: matchState.time + 1,
    events: [...matchState.events], // Copy events array
    homeTeam: {
        ...matchState.homeTeam,
        players: matchState.homeTeam.players.map(p => ({ ...p }))
    },
    awayTeam: {
        ...matchState.awayTeam,
        players: matchState.awayTeam.players.map(p => ({ ...p }))
    }
  };

  const { homeTeam, awayTeam } = newState;

  // --- Stamina Drain ---
  // Drain stamina for active players (0-10)
  [homeTeam, awayTeam].forEach(team => {
    for (let i = 0; i < 11; i++) {
        if (team.players[i]) {
            team.players[i].stamina -= random(0, 2); // 0-2 stamina per minute
            if (team.players[i].stamina < 0) team.players[i].stamina = 0;
        }
    }
  });

  // --- Event Logic ---
  const homeStats = calculateTeamStats(homeTeam.players);
  const awayStats = calculateTeamStats(awayTeam.players);

  // Midfield battle determines possession bias
  const totalMid = homeStats.midfield + awayStats.midfield;
  const homeProb = totalMid > 0 ? homeStats.midfield / totalMid : 0.5;

  // Base event chance
  if (Math.random() < 0.15) {
    const isHomeEvent = Math.random() < homeProb;
    const attackingTeam = isHomeEvent ? homeTeam : awayTeam;
    const defendingTeam = isHomeEvent ? awayTeam : homeTeam;
    const isHomeAttacking = isHomeEvent;

    // Pick active player
    const attackers = attackingTeam.players.slice(0, 11).filter(p => p.position === 'FWD' || p.position === 'MID');
    const activePlayer = attackers.length > 0
      ? attackers[random(0, attackers.length - 1)]
      : attackingTeam.players[random(0, 10)];

    const actionRoll = Math.random();

    // 1. Goal / Shot (30%)
    if (actionRoll < 0.30) {
       const isGoal = attemptGoal(activePlayer, defendingTeam);
       if (isGoal) {
         if (isHomeAttacking) newState.homeScore++; else newState.awayScore++;
         newState.events.unshift({
           id: Date.now() + Math.random(),
           minute: newState.time,
           type: 'goal',
           text: `GOAL! ${activePlayer.name} scores for ${attackingTeam.name}!`,
           teamId: attackingTeam.id,
           isHome: isHomeAttacking
         });
         // Boost rating
         activePlayer.matchRating += 1.0;
       } else {
         newState.events.unshift({
           id: Date.now() + Math.random(),
           minute: newState.time,
           type: 'miss',
           text: `${activePlayer.name} shoots... Saved by the keeper!`,
           teamId: attackingTeam.id,
           isHome: isHomeAttacking
         });
       }
    }
    // 2. Yellow Card (5%)
    else if (actionRoll < 0.35) {
        newState.events.unshift({
            id: Date.now() + Math.random(),
            minute: newState.time,
            type: 'card',
            text: `Yellow Card for ${activePlayer.name}`,
            teamId: attackingTeam.id,
            isHome: isHomeAttacking
        });
        activePlayer.matchRating -= 0.5;
    }
    // 3. Highlight/Pass (Rest)
    else {
        // Just flavor
        // const flavor = [`Nice pass by ${activePlayer.name}`, `${attackingTeam.name} keeping possession`];
        // newState.events.unshift({ minute: newState.time, type: 'highlight', text: flavor[random(0,1)], teamId: attackingTeam.id });
    }
  }

  // --- Substitutions ---
  // Check Home
  const homeSub = checkSubstitution(homeTeam, newState.time, newState.homeSubsUsed);
  if (homeSub) {
      const { playerOutIndex, playerInIndex } = homeSub;
      const playerOut = homeTeam.players[playerOutIndex];
      const playerIn = homeTeam.players[playerInIndex];

      // Swap logic: We move playerIn to the starting XI (index < 11) and playerOut to bench
      // Actually, standard array swap or move is better.
      // Ideally, we keep the array as [11 starters, ...bench].

      // Perform swap in the array
      homeTeam.players[playerOutIndex] = playerIn;
      homeTeam.players[playerInIndex] = playerOut;

      newState.homeSubsUsed++;
      newState.events.unshift({
          id: Date.now() + Math.random(),
          minute: newState.time,
          type: 'sub',
          text: `Substitution ${homeTeam.name}: ${playerIn.name} IN, ${playerOut.name} OUT`,
          teamId: homeTeam.id,
          isHome: true
      });
  }

  // Check Away
  const awaySub = checkSubstitution(awayTeam, newState.time, newState.awaySubsUsed);
  if (awaySub) {
      const { playerOutIndex, playerInIndex } = awaySub;
      const playerOut = awayTeam.players[playerOutIndex];
      const playerIn = awayTeam.players[playerInIndex];

      awayTeam.players[playerOutIndex] = playerIn;
      awayTeam.players[playerInIndex] = playerOut;

      newState.awaySubsUsed++;
      newState.events.unshift({
          id: Date.now() + Math.random(),
          minute: newState.time,
          type: 'sub',
          text: `Substitution ${awayTeam.name}: ${playerIn.name} IN, ${playerOut.name} OUT`,
          teamId: awayTeam.id,
          isHome: false
      });
  }

  return newState;
};
