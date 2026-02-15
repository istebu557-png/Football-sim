
import { calculateTeamStats, getStarRating, simulateMinute, cloneTeam } from '../src/utils/gameLogic.js';

console.log("Running Logic Tests...");

const mockTeam = {
  id: 'test',
  name: 'Test Team',
  players: [
    { name: 'GK', position: 'GK', rating: 90, physical: 90 },
    { name: 'DEF1', position: 'DEF', rating: 85, physical: 90 },
    { name: 'DEF2', position: 'DEF', rating: 85, physical: 90 },
    { name: 'DEF3', position: 'DEF', rating: 85, physical: 90 },
    { name: 'DEF4', position: 'DEF', rating: 85, physical: 90 },
    { name: 'MID1', position: 'MID', rating: 88, physical: 90 },
    { name: 'MID2', position: 'MID', rating: 88, physical: 90 },
    { name: 'MID3', position: 'MID', rating: 88, physical: 90 },
    { name: 'FWD1', position: 'FWD', rating: 92, physical: 90 },
    { name: 'FWD2', position: 'FWD', rating: 92, physical: 90 },
    { name: 'FWD3', position: 'FWD', rating: 92, physical: 90 },
    // Bench
    { name: 'Sub1', position: 'FWD', rating: 80, physical: 90 }
  ]
};

// Test Stats
const stats = calculateTeamStats(mockTeam.players);
console.log("Team Stats:", stats);
// (90 + 4*85 + 3*88 + 3*92) / 11 = (90 + 340 + 264 + 276) / 11 = 970 / 11 = 88.18... -> 88
if (stats.overall !== 88) {
    console.error(`FAILED: Overall stats calculation incorrect. Expected 88, got ${stats.overall}`);
    process.exit(1);
} else {
    console.log("PASSED: Overall stats");
}

// Test Stars (88 -> 4 stars (75-90))
const stars = getStarRating(stats.overall);
console.log("Stars:", stars);
if (stars !== 4) {
    console.error(`FAILED: Star calculation incorrect. Expected 4, got ${stars}`);
    process.exit(1);
} else {
    console.log("PASSED: Stars");
}

// Test Simulation Minute
const matchState = {
  time: 0,
  homeScore: 0,
  awayScore: 0,
  homeTeam: cloneTeam(mockTeam),
  awayTeam: cloneTeam(mockTeam),
  events: [],
  homeSubsUsed: 0,
  awaySubsUsed: 0
};

const newState = simulateMinute(matchState);
console.log("New Time:", newState.time);
if (newState.time !== 1) {
    console.error("FAILED: Time increment");
    process.exit(1);
} else {
    console.log("PASSED: Time increment");
}

// Check stamina drain logic
// Since random(0,2) is used, stamina should be <= original.
// Original stamina from cloneTeam uses p.physical (90).
const p1 = newState.homeTeam.players[0];
console.log("Player 1 Stamina:", p1.stamina);
if (p1.stamina > 90) {
    console.error("FAILED: Stamina logic (increased?)");
    process.exit(1);
} else {
    console.log("PASSED: Stamina logic");
}

console.log("All Logic Tests Completed Successfully.");
