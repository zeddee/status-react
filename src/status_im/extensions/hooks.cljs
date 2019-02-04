(ns status-im.extensions.hooks
  (:refer-clojure :exclude [list])
  (:require [status-im.chat.commands.core :as commands]
            [status-im.chat.commands.protocol :as protocol]
            [status-im.extensions.registry :as registry]))

(def wallet-settings
  {:properties
   {:label     :string
    :view      :view
    :on-opened :event
    :on-closed :event}
   :hook
   (reify registry/Hook
     (hook-in [_ id _ {:keys [label view _]} {:keys [db]}]
       (println "HOOKIN")
       {:db (assoc-in db [:wallet :settings id] {:label label :view view})})
     (unhook [_ id _ _ {:keys [db]}]
       {:db (update-in db [:wallet :settings] dissoc id)}))})

(def command-hook
  "Hook for extensions"
  {:properties
   {:description?   :string
    :scope          #{:personal-chats :public-chats :group-chats}
    :short-preview? :view
    :preview?       :view
    :on-send?       :event
    :on-receive?    :event
    :on-send-sync?  :event
    :parameters?     [{:id           :keyword
                       :type         {:one-of #{:text :phone :password :number}}
                       :placeholder  :string
                       :suggestions? :view}]}
   :hook
   (reify registry/Hook
     (hook-in [_ id {extension-id :id} {:keys [description scope parameters preview short-preview
                                               on-send on-receive on-send-sync]} cofx]
       (let [new-command (if on-send-sync
                           (reify protocol/Command
                             (id [_] (name id))
                             (scope [_] scope)
                             (description [_] description)
                             (parameters [_] (or parameters []))
                             (validate [_ _ _])
                             (on-send [_ command-message _] (when on-send {:dispatch (on-send command-message)}))
                             (on-receive [_ command-message _] (when on-receive {:dispatch (on-receive command-message)}))
                             (short-preview [_ props] (when short-preview (short-preview props)))
                             (preview [_ props] (when preview (preview props)))
                             protocol/Yielding
                             (yield-control [_ props _] {:dispatch (on-send-sync props)})
                             protocol/Extension
                             (extension-id [_] extension-id))
                           (reify protocol/Command
                             (id [_] (name id))
                             (scope [_] scope)
                             (description [_] description)
                             (parameters [_] (or parameters []))
                             (validate [_ _ _])
                             (on-send [_ command-message _] (when on-send {:dispatch (on-send command-message)}))
                             (on-receive [_ command-message _] (when on-receive {:dispatch (on-receive command-message)}))
                             (short-preview [_ props] (when short-preview (short-preview props)))
                             (preview [_ props] (when preview (preview props)))
                             protocol/Extension
                             (extension-id [_] extension-id)))]
         (commands/load-commands cofx [new-command])))
     (unhook [_ id _ {:keys [scope]} {:keys [db] :as cofx}]
       (commands/remove-command (get-in db [:id->command [(name id) scope] :type]) cofx)))})
