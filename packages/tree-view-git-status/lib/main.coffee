{CompositeDisposable} = require 'atom'
path = require 'path'

module.exports = TreeViewGitStatus =
  config:
    autoToggle:
      type: 'boolean'
      default: true
    showProjectModifiedStatus:
      type: 'boolean'
      default: true
      description:
        'Mark project folder as modified in case there are any ' +
        'uncommited changes'
    showBranchLabel:
      type: 'boolean'
      default: true
    showCommitsAheadLabel:
      type: 'boolean'
      default: true
    showCommitsBehindLabel:
      type: 'boolean'
      default: true

  subscriptions: null
  repositorySubscriptions: null
  repositoryMap: null
  treeView: null
  treeViewRootsMap: null
  roots: null
  showProjectModifiedStatus: true
  showBranchLabel: true
  showCommitsAheadLabel: true
  showCommitsBehindLabel: true
  subscriptionsOfCommands: null
  active: false

  activate: ->
    @active = true

    # Read configuration
    @showProjectModifiedStatus =
      atom.config.get 'tree-view-git-status.showProjectModifiedStatus'
    @showBranchLabel =
      atom.config.get 'tree-view-git-status.showBranchLabel'
    @showCommitsAheadLabel =
      atom.config.get 'tree-view-git-status.showCommitsAheadLabel'
    @showCommitsBehindLabel =
      atom.config.get 'tree-view-git-status.showCommitsBehindLabel'

    # Commands Subscriptions
    @subscriptionsOfCommands = new CompositeDisposable
    @subscriptionsOfCommands.add atom.commands.add 'atom-workspace',
      'tree-view-git-status:toggle': =>
        @toggle()

    @subscriptions = new CompositeDisposable

    @toggle() if atom.config.get 'tree-view-git-status.autoToggle'

  deactivate: ->
    @subscriptions?.dispose()
    @repositorySubscriptions?.dispose()
    @subscriptionsOfCommands?.dispose()
    @clearRoots() if @treeView?
    @repositoryMap?.clear()
    @treeViewRootsMap?.clear()
    @subscriptions = null
    @treeView = null
    @repositorySubscriptions = null
    @treeViewRootsMap = null
    @repositoryMap = null
    @active = false
    @toggled = false

  toggle: ->
    return unless @active
    if @toggled
      @toggled = false
      @subscriptions?.dispose()
      @repositorySubscriptions?.dispose()
      @clearRoots() if @treeView?
      @treeViewRootsMap?.clear()
      @repositoryMap?.clear()
    else
      @toggled = true
      # Setup subscriptions
      @subscriptions.add atom.project.onDidChangePaths =>
        @subscribeUpdateRepositories()
      @subscribeUpdateRepositories()
      @subscribeUpdateConfigurations()

      atom.packages.activatePackage('tree-view').then (treeViewPkg) =>
        return unless @active and @toggled
        @treeView = treeViewPkg.mainModule.createView()
        # Bind against events which are causing an update of the tree view
        @subscribeUpdateTreeView()
        # Update the tree roots
        @updateRoots true
      .catch (error) ->
        console.error error, error.stack

  clearRoots: ->
    for root in @roots
      rootPath = path.normalize root.directoryName.dataset.path
      root.classList.remove('status-modified')
      customElements = @treeViewRootsMap.get(rootPath).customElements
      if customElements?.headerGitStatus?
        root.header.removeChild(customElements.headerGitStatus)

  subscribeUpdateConfigurations: ->
    atom.config.observe 'tree-view-git-status.showProjectModifiedStatus',
      (newValue) =>
        if @showProjectModifiedStatus isnt newValue
          @showProjectModifiedStatus = newValue
          @updateRoots()

    atom.config.observe 'tree-view-git-status.showBranchLabel',
      (newValue) =>
        if @showBranchLabel isnt newValue
          @showBranchLabel = newValue
          @updateRoots()

    atom.config.observe 'tree-view-git-status.showCommitsAheadLabel',
      (newValue) =>
        if @showCommitsAheadLabel isnt newValue
          @showCommitsAheadLabel = newValue
          @updateRoots()

    atom.config.observe 'tree-view-git-status.showCommitsBehindLabel',
      (newValue) =>
        if @showCommitsBehindLabel isnt newValue
          @showCommitsBehindLabel = newValue
          @updateRoots()

  subscribeUpdateTreeView: ->
    @subscriptions.add(
      atom.project.onDidChangePaths =>
        @updateRoots true
    )
    @subscriptions.add(
      atom.config.onDidChange 'tree-view.hideVcsIgnoredFiles', =>
        @updateRoots true
    )
    @subscriptions.add(
      atom.config.onDidChange 'tree-view.hideIgnoredNames', =>
        @updateRoots true
    )
    @subscriptions.add(
      atom.config.onDidChange 'core.ignoredNames', =>
        @updateRoots true if atom.config.get 'tree-view.hideIgnoredNames'
    )
    @subscriptions.add(
      atom.config.onDidChange 'tree-view.sortFoldersBeforeFiles', =>
        @updateRoots true
    )

  subscribeUpdateRepositories: ->
    @repositorySubscriptions?.dispose()
    @repositorySubscriptions = new CompositeDisposable
    @repositoryMap = new Map()
    for repo in atom.project.getRepositories() when repo?
      @repositoryMap.set(path.normalize(repo.getWorkingDirectory()), repo)
      @subscribeToRepo repo

  subscribeToRepo: (repo) ->
    @repositorySubscriptions.add repo.onDidChangeStatuses =>
      @updateRootForRepo repo
    @repositorySubscriptions.add repo.onDidChangeStatus =>
      @updateRootForRepo repo

  updateRoots: (reset) ->
    if @treeView?
      if not @treeViewRootsMap? then reset = true
      @roots = @treeView.roots
      @treeViewRootsMap = new Map() if reset
      for root in @roots
        rootPath = path.normalize root.directoryName.dataset.path
        if reset
          @treeViewRootsMap.set(rootPath, {root, customElements: {}})
        repoForRoot = null
        repoSubPath = null
        @repositoryMap.forEach (repo, repoPath) ->
          if rootPath.indexOf(repoPath) is 0
            repoSubPath = path.relative repoPath, rootPath
            repoForRoot = repo
        if repoForRoot?
          @doUpdateRootNode root, repoForRoot, rootPath, repoSubPath

  updateRootForRepo: (repo) ->
    if @treeView? and @treeViewRootsMap?
      repoPath = path.normalize repo.getWorkingDirectory()
      @treeViewRootsMap.forEach (root, rootPath) =>
        if rootPath.indexOf(repoPath) is 0
          repoSubPath = path.relative repoPath, rootPath
          @doUpdateRootNode root.root, repo, rootPath, repoSubPath if root.root?

  doUpdateRootNode: (root, repo, rootPath, repoSubPath) ->
    customElements = @treeViewRootsMap.get(rootPath).customElements

    isModified = false
    if @showProjectModifiedStatus and repo?
      if repoSubPath isnt '' and repo.getDirectoryStatus(repoSubPath) isnt 0
        isModified = true
      else if repoSubPath is ''
        # Workaround for the issue that 'getDirectoryStatus' doesn't work
        # on the repository root folder
        isModified = @isRepoModified repo
    if isModified
      root.classList.add('status-modified')
    else
      root.classList.remove('status-modified')

    showHeaderGitStatus = @showBranchLabel or @showCommitsAheadLabel or
        @showCommitsBehindLabel

    if showHeaderGitStatus and repo? and not customElements.headerGitStatus?
      headerGitStatus = document.createElement('span')
      headerGitStatus.classList.add('tree-view-git-status')
      @generateGitStatusText headerGitStatus, repo
      root.header.insertBefore(headerGitStatus, root.directoryName.nextSibling)
      customElements.headerGitStatus = headerGitStatus
    else if showHeaderGitStatus and customElements.headerGitStatus?
      @generateGitStatusText customElements.headerGitStatus, repo
    else if customElements.headerGitStatus?
      root.header.removeChild(customElements.headerGitStatus)
      customElements.headerGitStatus = null

  generateGitStatusText: (container, repo) ->
    display = false
    head = repo?.getShortHead()
    {ahead, behind} = repo.getCachedUpstreamAheadBehindCount() ? {}
    if @showBranchLabel and head?
      branchLabel = document.createElement('span')
      branchLabel.classList.add('branch-label')
      branchLabel.textContent = head
      display = true
    if @showCommitsAheadLabel and ahead > 0
      commitsAhead = document.createElement('span')
      commitsAhead.classList.add('commits-ahead-label')
      commitsAhead.textContent = ahead
      display = true
    if @showCommitsBehindLabel and behind > 0
      commitsBehind = document.createElement('span')
      commitsBehind.classList.add('commits-behind-label')
      commitsBehind.textContent = behind
      display = true

    if display
      container.classList.remove('hide')
    else
      container.classList.add('hide')

    container.innerHTML = ''
    container.appendChild branchLabel if branchLabel?
    container.appendChild commitsAhead if commitsAhead?
    container.appendChild commitsBehind if commitsBehind?

  isRepoModified: (repo) ->
    return Object.keys(repo.statuses).length > 0
