import React, { useEffect, useRef, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { supabase, missingSupabaseSettings } from './supabase';
import './style.css';

const MAX_FILE_SIZE = 20 * 1024 * 1024;
const ACCEPTED_FILES = [
  'image/jpeg', 'image/png', 'image/gif', 'image/webp',
  '.pdf', '.doc', '.docx', '.xls', '.xlsx', '.txt', '.csv',
].join(',');

function Icon({ name, size = 20 }) {
  const paths = {
    lock: <><rect x="4" y="10" width="16" height="11" rx="2" /><path d="M8 10V7a4 4 0 1 1 8 0v3" /><path d="M12 14v3" /></>,
    paperclip: <path d="m21.4 11.6-8.5 8.5a6 6 0 0 1-8.5-8.5l9.2-9.2a4 4 0 0 1 5.7 5.7l-9.2 9.2a2 2 0 0 1-2.8-2.8l8.5-8.5" />,
    send: <><path d="m22 2-7 20-4-9-9-4Z" /><path d="M22 2 11 13" /></>,
    image: <><rect x="3" y="3" width="18" height="18" rx="3" /><circle cx="8.5" cy="8.5" r="1.5" /><path d="m21 15-5-5L5 21" /></>,
    file: <><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8Z" /><path d="M14 2v6h6M8 13h8M8 17h8" /></>,
    check: <path d="m5 12 4 4L19 6" />,
  };
  return <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">{paths[name]}</svg>;
}

function BrandMark({ mini = false }) {
  return mini
    ? <div className="mini-mark">u<span>&</span>u</div>
    : <div className="brand-mark"><span>u</span><span>&</span><span>u</span></div>;
}

function SetupNeeded() {
  return (
    <main className="setup-screen">
      <div className="setup-card">
        <BrandMark />
        <div className="eyebrow">MADE FOR TWO</div>
        <h1>A little place<br />for just us.</h1>
        <p className="setup-copy">Connect your Supabase project to turn on email sign-in and private file sharing. Add the project URL and publishable key to the private .env file, then set up the two approved email addresses in Supabase.</p>
        <div className="setup-note"><Icon name="lock" size={17} /><span>Only the two approved email accounts can use this chat.</span></div>
        <p className="setup-small">Setup steps are in the project README.</p>
      </div>
    </main>
  );
}

function AuthGate({ onDone }) {
  const [mode, setMode] = useState('signin');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [name, setName] = useState('');
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState('');
  const [info, setInfo] = useState('');

  const submit = async (event) => {
    event.preventDefault();
    if (busy) return;
    setBusy(true);
    setError('');
    setInfo('');
    const normalizedEmail = email.trim().toLowerCase();
    try {
      if (mode === 'signup') {
        const { data, error: signUpError } = await supabase.auth.signUp({
          email: normalizedEmail,
          password,
          options: { data: { display_name: name.trim() } },
        });
        if (signUpError) throw signUpError;
        if (!data.session) {
          setInfo('Check your email to confirm your account, then come back here to sign in.');
        } else {
          onDone(data.user);
        }
      } else {
        const { data, error: signInError } = await supabase.auth.signInWithPassword({
          email: normalizedEmail,
          password,
        });
        if (signInError) throw signInError;
        onDone(data.user);
      }
    } catch (err) {
      setError(err.message || 'Could not sign in. Please try again.');
    } finally {
      setBusy(false);
    }
  };

  return (
    <main className="gate-screen">
      <div className="gate-card">
        <BrandMark />
        <div className="eyebrow">MADE FOR TWO</div>
        <h1>A little place<br />for just us.</h1>
        <p className="gate-subtitle">Your quiet corner of the internet.</p>
        <form onSubmit={submit} className="auth-form">
          {mode === 'signup' && (
            <label className="field-label auth-field">
              YOUR NAME
              <input value={name} onChange={(e) => setName(e.target.value)} maxLength={40} placeholder="What should we call you?" autoComplete="name" required />
            </label>
          )}
          <label className="field-label auth-field">
            EMAIL ADDRESS
            <input type="email" value={email} onChange={(e) => setEmail(e.target.value)} placeholder="you@example.com" autoComplete="email" required />
          </label>
          <label className="field-label auth-field">
            PASSWORD
            <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} minLength={8} placeholder="At least 8 characters" autoComplete={mode === 'signup' ? 'new-password' : 'current-password'} required />
          </label>
          {error && <p className="error-message" role="alert">{error}</p>}
          {info && <p className="info-message" role="status">{info}</p>}
          <button className="primary-button" disabled={busy || !email.trim() || password.length < 8 || (mode === 'signup' && !name.trim())}>
            {busy ? <span className="spinner" /> : <Icon name="lock" size={17} />}
            {busy ? 'Please wait…' : mode === 'signup' ? 'Create account' : 'Sign in'}
          </button>
        </form>
        <p className="auth-toggle">
          {mode === 'signin' ? 'New here?' : 'Already have an account?'}
          <button onClick={() => { setMode(mode === 'signin' ? 'signup' : 'signin'); setError(''); setInfo(''); }}>
            {mode === 'signin' ? 'Create account' : 'Sign in'}
          </button>
        </p>
        <div className="gate-footnote"><span className="pulse-dot" /> Only the two approved email addresses can join</div>
        <div className="gate-bottom"><span className="tiny-heart">♡</span> a private place for two</div>
      </div>
    </main>
  );
}

function AccessDenied({ email, onSignOut }) {
  return (
    <main className="gate-screen">
      <div className="gate-card">
        <BrandMark />
        <div className="eyebrow">MADE FOR TWO</div>
        <h1>This chat is<br />just for two.</h1>
        <p className="gate-subtitle">{email} is not on the approved list for this chat.</p>
        <button className="primary-button access-signout" onClick={onSignOut}><Icon name="lock" size={17} /> Sign out</button>
        <div className="gate-bottom"><span className="tiny-heart">♡</span> a private place for two</div>
      </div>
    </main>
  );
}

function fileSize(bytes) {
  if (bytes < 1024 * 1024) return Math.max(1, Math.round(bytes / 1024)) + ' KB';
  return (bytes / (1024 * 1024)).toFixed(1) + ' MB';
}

function displayName(user) {
  return user.user_metadata?.display_name || user.email || 'You';
}

function Message({ message, user, downloading, onDownload }) {
  const mine = message.sender_id === user.id;
  const time = message.created_at
    ? new Date(message.created_at).toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })
    : '';
  return (
    <article className={'message-row ' + (mine ? 'mine' : 'theirs')}>
      {!mine && <div className="message-avatar">{(message.sender_name || '?').slice(0, 1).toUpperCase()}</div>}
      <div className="message-content">
        {!mine && <div className="sender-name">{message.sender_name}</div>}
        <div className={'bubble ' + (message.file_name ? 'file-bubble' : '')}>
          {message.file_name && (
            <div className="ephemeral-file">
              <span className="file-icon"><Icon name={message.file_type?.startsWith('image/') ? 'image' : 'file'} size={19} /></span>
              <span className="file-details">
                <strong>{message.file_name}</strong>
                <small>{fileSize(message.file_size || 0)}</small>
              </span>
              {message.downloaded_at ? (
                <span className="removed-label">Downloaded<br />and removed</span>
              ) : mine ? (
                <span className="waiting-label">Waiting for<br />their download</span>
              ) : (
                <button className="download-once" onClick={() => onDownload(message)} disabled={downloading === message.id}>
                  {downloading === message.id ? 'Getting file…' : 'Download once'}
                </button>
              )}
            </div>
          )}
          {message.body && <p>{message.body}</p>}
        </div>
        <div className="message-meta">{time}{mine && <span className="sent-check"><Icon name="check" size={13} /></span>}</div>
      </div>
      {mine && <div className="message-avatar mine-avatar">{(message.sender_name || '?').slice(0, 1).toUpperCase()}</div>}
    </article>
  );
}

function Chat({ user, onLock }) {
  const [messages, setMessages] = useState([]);
  const [text, setText] = useState('');
  const [busy, setBusy] = useState(false);
  const [downloading, setDownloading] = useState('');
  const [error, setError] = useState('');
  const messageEndRef = useRef(null);
  const fileInputRef = useRef(null);
  const inputRef = useRef(null);

  useEffect(() => {
    let active = true;
    const load = async () => {
      const { data, error: queryError } = await supabase
        .from('chat_messages')
        .select('*')
        .order('created_at', { ascending: true })
        .limit(500);
      if (!active) return;
      if (queryError) setError('Could not load messages. Check your Supabase setup.');
      else setMessages(data || []);
    };
    load();
    const channel = supabase
      .channel('private-chat-messages')
      .on('postgres_changes', { event: '*', schema: 'public', table: 'chat_messages' }, (payload) => {
        const changed = payload.new;
        if (!changed?.id) return;
        setMessages((current) => {
          const next = current.filter((message) => message.id !== changed.id);
          next.push(changed);
          return next.sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
        });
      })
      .subscribe();
    return () => {
      active = false;
      supabase.removeChannel(channel);
    };
  }, [user.id]);

  useEffect(() => {
    messageEndRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages.length]);

  const partner = messages.find((message) => message.sender_id !== user.id);
  const otherName = partner?.sender_name || 'your person';
  const mineName = displayName(user);

  const sendText = async (event) => {
    event.preventDefault();
    const clean = text.trim();
    if (!clean || busy) return;
    setBusy(true);
    setError('');
    const { error: insertError } = await supabase.from('chat_messages').insert({
      sender_id: user.id,
      sender_name: mineName,
      body: clean,
    });
    if (insertError) setError('Could not send that message. Check your connection and try again.');
    else {
      setText('');
      inputRef.current?.focus();
    }
    setBusy(false);
  };

  const sendFile = async (file) => {
    if (!file) return;
    setError('');
    if (file.size > MAX_FILE_SIZE) {
      setError('Please choose a file smaller than 20 MB.');
      return;
    }
    if (!file.type) {
      setError('This file type could not be identified. Try a common image or document.');
      return;
    }
    setBusy(true);
    const safeName = file.name.replace(/[^\w.\- ()]/g, '_').slice(0, 160);
    const path = user.id + '/' + crypto.randomUUID() + '-' + safeName;
    const { error: uploadError } = await supabase.storage.from('chat-files').upload(path, file, {
      contentType: file.type,
      upsert: false,
    });
    if (uploadError) {
      setError('That file could not be uploaded. Check the file type and connection.');
      setBusy(false);
      if (fileInputRef.current) fileInputRef.current.value = '';
      return;
    }
    const { error: messageError } = await supabase.from('chat_messages').insert({
      sender_id: user.id,
      sender_name: mineName,
      body: null,
      file_path: path,
      file_name: file.name.slice(0, 200),
      file_type: file.type,
      file_size: file.size,
    });
    if (messageError) {
      await supabase.storage.from('chat-files').remove([path]);
      setError('The upload finished, but the file could not be added to chat.');
    }
    setBusy(false);
    if (fileInputRef.current) fileInputRef.current.value = '';
  };

  const downloadFile = async (message) => {
    if (!message.file_path || message.sender_id === user.id || downloading) return;
    setDownloading(message.id);
    setError('');
    const { data: blob, error: downloadError } = await supabase.storage.from('chat-files').download(message.file_path);
    if (downloadError || !blob) {
      setError('That file is no longer available. Ask them to send it again.');
      setDownloading('');
      return;
    }

    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = message.file_name;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    await new Promise((resolve) => setTimeout(resolve, 700));
    URL.revokeObjectURL(url);

    const { error: deleteError } = await supabase.storage.from('chat-files').remove([message.file_path]);
    if (deleteError) {
      setError('The download finished, but automatic file removal failed. Please try again.');
      setDownloading('');
      return;
    }

    const { data: marked, error: markError } = await supabase.rpc('mark_chat_file_downloaded', {
      p_message_id: message.id,
    });
    if (markError || !marked) {
      setError('The file was removed, but its chat note could not be updated. Refresh the page.');
    } else {
      setMessages((current) => current.map((row) => row.id === message.id
        ? { ...row, file_path: null, downloaded_at: new Date().toISOString(), downloaded_by: user.id }
        : row));
    }
    setDownloading('');
  };

  const onDrop = (event) => {
    event.preventDefault();
    sendFile(event.dataTransfer.files?.[0]);
  };

  return (
    <main className="chat-shell" onDragOver={(e) => e.preventDefault()} onDrop={onDrop}>
      <aside className="sidebar">
        <div className="sidebar-brand"><BrandMark mini /><span>just us</span></div>
        <div className="sidebar-section-label">YOUR SPACE</div>
        <div className="conversation-card active">
          <div className="pair-avatar"><span>{mineName[0]?.toUpperCase() || 'Y'}</span><span>{otherName[0]?.toUpperCase() || '♡'}</span></div>
          <span className="conversation-copy"><strong>You & {otherName}</strong><small>{messages.at(-1)?.body || (messages.length ? 'Shared a file' : 'Your story starts here')}</small></span>
          <span className="unread-dot" />
        </div>
        <div className="sidebar-bottom">
          <div className="privacy-card"><span className="privacy-icon"><Icon name="lock" size={16} /></span><div><strong>A space for two</strong><small>Email protected</small></div></div>
          <button className="lock-button" onClick={onLock}><Icon name="lock" size={16} /> Sign out</button>
        </div>
      </aside>

      <section className="chat-panel">
        <header className="chat-header">
          <div className="chat-title-wrap">
            <div className="pair-avatar header-avatar"><span>{mineName[0]?.toUpperCase() || 'Y'}</span><span>{otherName[0]?.toUpperCase() || '♡'}</span></div>
            <div className="chat-title"><h2>You & {otherName}</h2><span className="presence"><i className={partner ? 'online-dot' : 'offline-dot'} />{partner ? 'Your private conversation' : 'Waiting for your person'}</span></div>
          </div>
          <div className="header-actions">
            <span className="secure-label"><Icon name="lock" size={14} /> PRIVATE CHAT</span>
            <button className="icon-button mobile-lock" aria-label="Sign out" onClick={onLock}><Icon name="lock" size={18} /></button>
          </div>
        </header>

        <div className="messages-area">
          <div className="date-chip"><span>✦</span> just between us <span>✦</span></div>
          {messages.length === 0 ? (
            <div className="empty-state">
              <div className="empty-art"><span className="empty-circle one" /><span className="empty-circle two" /><div className="empty-heart">♡</div></div>
              <p className="empty-kicker">A FRESH START</p>
              <h3>Your conversation<br />starts right here.</h3>
              <p className="empty-hint">Say hello, share a photo, or send something<br className="desktop-break" /> you know will make them smile.</p>
            </div>
          ) : (
            <div className="message-list">
              <div className="message-day">YOUR CONVERSATION</div>
              {messages.map((message) => <Message key={message.id} message={message} user={user} downloading={downloading} onDownload={downloadFile} />)}
              <div ref={messageEndRef} />
            </div>
          )}
        </div>

        <div className="compose-wrap">
          {error && <div className="chat-error" role="alert">{error}</div>}
          <div className="compose-box">
            <button className="attach-button" onClick={() => fileInputRef.current?.click()} aria-label="Attach an image or document" title="Share an image or document" disabled={busy}><Icon name="paperclip" size={21} /></button>
            <input ref={fileInputRef} type="file" accept={ACCEPTED_FILES} hidden onChange={(e) => sendFile(e.target.files?.[0])} />
            <form onSubmit={sendText} className="message-form">
              <input ref={inputRef} value={text} onChange={(e) => setText(e.target.value)} placeholder="Write a little something…" maxLength={4000} />
              <span className="compose-hint">ENTER TO SEND</span>
              <button className="send-button" aria-label="Send message" disabled={busy || !text.trim()}><Icon name="send" size={17} /></button>
            </form>
          </div>
          <div className="compose-caption"><span>Files are removed after the other person downloads them</span><span>Images & documents · Up to 20 MB</span></div>
        </div>
      </section>
    </main>
  );
}

function App() {
  const [user, setUser] = useState(null);
  const [booting, setBooting] = useState(true);
  const [membership, setMembership] = useState('checking');

  useEffect(() => {
    if (!supabase) {
      setBooting(false);
      return;
    }
    supabase.auth.getSession().then(({ data }) => {
      setUser(data.session?.user || null);
      setBooting(false);
    });
    const { data: listener } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user || null);
    });
    return () => listener.subscription.unsubscribe();
  }, []);

  useEffect(() => {
    let active = true;
    if (!user) {
      setMembership('signed-out');
      return () => { active = false; };
    }
    setMembership('checking');
    supabase.from('chat_members').select('user_id').eq('user_id', user.id).maybeSingle()
      .then(({ data, error }) => {
        if (active) setMembership(!error && data ? 'member' : 'denied');
      });
    return () => { active = false; };
  }, [user]);

  const signOut = async () => {
    await supabase.auth.signOut();
    setUser(null);
    setMembership('signed-out');
  };

  if (missingSupabaseSettings.length) return <SetupNeeded />;
  if (booting || (user && membership === 'checking')) return <main className="loading-screen"><BrandMark mini /><span>Opening your little space…</span></main>;
  if (!user) return <AuthGate onDone={setUser} />;
  if (membership !== 'member') return <AccessDenied email={user.email} onSignOut={signOut} />;
  return <Chat user={user} onLock={signOut} />;
}

createRoot(document.getElementById('root')).render(<App />);
