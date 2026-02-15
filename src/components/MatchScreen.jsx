
import React, { useState, useEffect, useRef } from 'react';
import { simulateMinute, cloneTeam } from '../utils/gameLogic';
import TeamCard from './TeamCard';

const MatchScreen = ({ homeTeam, awayTeam, onEnd }) => {
  const [matchState, setMatchState] = useState(null);
  const [isPlaying, setIsPlaying] = useState(false);
  const [speed, setSpeed] = useState(500); // ms per minute
  const eventsEndRef = useRef(null);

  // Initialize match
  useEffect(() => {
    // Clone teams to avoid mutating global data
    const initialHome = cloneTeam(homeTeam);
    const initialAway = cloneTeam(awayTeam);

    setMatchState({
      time: 0,
      homeScore: 0,
      awayScore: 0,
      homeTeam: initialHome,
      awayTeam: initialAway,
      events: [],
      homeSubsUsed: 0,
      awaySubsUsed: 0
    });
  }, [homeTeam, awayTeam]);

  // Game Loop
  useEffect(() => {
    let interval = null;
    if (isPlaying) {
      interval = setInterval(() => {
        setMatchState(prevState => {
            if (!prevState || prevState.time >= 90) {
                setIsPlaying(false);
                return prevState;
            }
            return simulateMinute(prevState);
        });
      }, speed);
    }
    return () => clearInterval(interval);
  }, [isPlaying, speed]);

  // Scroll to new events
  useEffect(() => {
      // Logic to scroll to top of list as new events are added via unshift (top)
      // Actually, if using flex-col-reverse or similar, it handles itself.
      // But typically logs scroll to bottom.
      // My logic adds new events to start (unshift).
  }, [matchState?.events]);


  if (!matchState) return <div>Loading Match...</div>;

  const { time, homeScore, awayScore, events, homeTeam: currentHome, awayTeam: currentAway } = matchState;

  return (
    <div className="match-screen">
      {/* Scoreboard */}
      <div className="scoreboard">
        <div className="team-score home">
          <div className="team-name">{currentHome.name}</div>
          <div className="score">{homeScore}</div>
        </div>
        <div className="timer">
          <div className="minute">{time}'</div>
          <div className="status">{time >= 90 ? "Full Time" : isPlaying ? "Live" : "Paused"}</div>
        </div>
        <div className="team-score away">
          <div className="score">{awayScore}</div>
          <div className="team-name">{currentAway.name}</div>
        </div>
      </div>

      {/* Controls */}
      <div className="match-controls">
        {time < 90 ? (
            <button onClick={() => setIsPlaying(!isPlaying)}>
            {isPlaying ? "Pause" : "Resume"}
            </button>
        ) : (
            <button onClick={onEnd} className="end-btn">Finish Match</button>
        )}

        <div className="speed-controls">
            <span>Speed: </span>
            <button onClick={() => setSpeed(1000)} disabled={speed === 1000}>1x</button>
            <button onClick={() => setSpeed(200)} disabled={speed === 200}>5x</button>
            <button onClick={() => setSpeed(50)} disabled={speed === 50}>20x</button>
        </div>
      </div>

      <div className="match-content">
        {/* Lineups / Ratings */}
        <div className="lineups">
            <div className="team-lineup">
                <h3>{currentHome.name} Ratings</h3>
                <ul>
                    {currentHome.players.slice(0, 11).map((p, i) => (
                        <li key={i} className={p.stamina < 50 ? 'tired' : ''}>
                            <span className="pos">{p.position}</span>
                            <span className="name">{p.name}</span>
                            <div className="stamina-track">
                                <div className="stamina-fill" style={{width: `${p.stamina}%`}}></div>
                            </div>
                            <span className="rating">{p.matchRating.toFixed(1)}</span>
                        </li>
                    ))}
                </ul>
            </div>
             <div className="team-lineup">
                <h3>{currentAway.name} Ratings</h3>
                <ul>
                    {currentAway.players.slice(0, 11).map((p, i) => (
                        <li key={i} className={p.stamina < 50 ? 'tired' : ''}>
                            <span className="pos">{p.position}</span>
                            <span className="name">{p.name}</span>
                            <div className="stamina-track">
                                <div className="stamina-fill" style={{width: `${p.stamina}%`}}></div>
                            </div>
                            <span className="rating">{p.matchRating.toFixed(1)}</span>
                        </li>
                    ))}
                </ul>
            </div>
        </div>

        {/* Commentary Feed */}
        <div className="commentary">
            <h3>Live Commentary</h3>
            <div className="events-list">
                {events.length === 0 && <p className="no-events">Match is starting...</p>}
                {events.map((ev, i) => (
                    <div key={ev.id || i} className={`event-item ${ev.type}`}>
                        <span className="event-time">{ev.minute}'</span>
                        <span className="event-text">{ev.text}</span>
                    </div>
                ))}
            </div>
        </div>
      </div>
    </div>
  );
};

export default MatchScreen;
